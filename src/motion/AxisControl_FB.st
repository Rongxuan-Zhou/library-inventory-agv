// =============================================================================
// AxisControl_FB — Encapsulated Single-Axis Motion Controller
// =============================================================================
// Provides a unified interface for controlling one EtherCAT axis (XINJE DP3C)
// through SoftMotion. Handles power-on sequencing, homing, absolute/relative
// moves, jog, halt, stop, and fault recovery.
//
// Usage: Instantiate once per physical axis. Call cyclically from MainTask.
//
// Dependencies:
//   - CODESYS SoftMotion V4.15 (SM3_Basic, SM3_Drive_ETC)
//   - AXIS_REF_ETC_DS402_CS axis reference
// =============================================================================

FUNCTION_BLOCK AxisControl_FB
VAR_INPUT
    stAxisRef       : REFERENCE TO AXIS_REF_ETC_DS402_CS;

    // Commands (active on rising edge)
    bEnable         : BOOL;     // Power on/off
    bHome           : BOOL;     // Start homing
    bMoveAbs        : BOOL;     // Start absolute move
    bMoveRel        : BOOL;     // Start relative move
    bMoveVel        : BOOL;     // Start velocity move
    bJogPos         : BOOL;     // Jog positive direction
    bJogNeg         : BOOL;     // Jog negative direction
    bHalt           : BOOL;     // Controlled stop
    bStop           : BOOL;     // Emergency stop
    bReset          : BOOL;     // Fault reset

    // Motion parameters
    rPosition       : LREAL;    // Target position (mm) for MoveAbs
    rDistance        : LREAL;    // Distance (mm) for MoveRel
    rVelocity       : LREAL;    // Velocity (mm/s)
    rAcceleration   : LREAL;    // Acceleration (mm/s²)
    rDeceleration   : LREAL;    // Deceleration (mm/s²)
    rJerk           : LREAL;    // Jerk (mm/s³) — set >0 for S-curve
    rJogVelocity    : LREAL;    // Jog speed (mm/s)
END_VAR

VAR_OUTPUT
    bEnabled        : BOOL;     // Axis is powered and ready
    bHomed          : BOOL;     // Homing completed successfully
    bMoving         : BOOL;     // Axis is in motion
    bInPosition     : BOOL;     // Move completed, axis at target
    bError          : BOOL;     // Axis is in error state
    nErrorID        : UDINT;    // SoftMotion error code
    rActPosition    : LREAL;    // Current position (mm)
    rActVelocity    : LREAL;    // Current velocity (mm/s)
END_VAR

VAR
    // MC function block instances
    fbPower         : MC_Power_ETC;
    fbHome          : MC_Home_ETC;
    fbMoveAbs       : MC_MoveAbsolute_ETC;
    fbMoveRel       : MC_MoveRelative_ETC;
    fbMoveVel       : MC_MoveVelocity_ETC;
    fbJog           : MC_Jog_ETC;
    fbHalt          : MC_Halt_ETC;
    fbStop          : MC_Stop_ETC;
    fbReset         : MC_Reset_ETC;
    fbSetPos        : MC_SetPosition_ETC;
    fbReadPos       : MC_ReadParameter;
    fbReadVel       : MC_ReadParameter;

    // Edge detection for single-shot commands
    rtHome          : R_TRIG;
    rtMoveAbs       : R_TRIG;
    rtMoveRel       : R_TRIG;
    rtMoveVel       : R_TRIG;
    rtReset         : R_TRIG;

    bHomeDone       : BOOL;
END_VAR

// ---------------------------------------------------------------------------
// Power Management
// ---------------------------------------------------------------------------
// MC_Power is level-triggered (Enable input), not edge-triggered.
// When bEnable goes TRUE → drive transitions through DS402 states to
// "Operation Enabled". When FALSE → drive returns to "Switch On Disabled".

fbPower(
    Axis            := stAxisRef,
    Enable          := bEnable,
    bRegulatorOn    := bEnable,
    bDriveStart     := bEnable
);

bEnabled := fbPower.Status;

// ---------------------------------------------------------------------------
// Homing
// ---------------------------------------------------------------------------
// Triggered on rising edge of bHome. The homing method is configured in the
// drive via SDO 0x6098 (set during commissioning in CODESYS device config).
// Homing velocities are configured via SDO 0x6099.
//
// After successful homing, the encoder position is calibrated via MC_SetPosition.

rtHome(CLK := bHome);
fbHome(
    Axis            := stAxisRef,
    Execute         := rtHome.Q,
    bCalibrationCam := FALSE    // Using drive-internal homing
);

IF fbHome.Done AND NOT bHomeDone THEN
    bHomeDone := TRUE;
    // Optionally reset position counter to zero after homing
    fbSetPos(
        Axis     := stAxisRef,
        Execute  := TRUE,
        Position := 0.0
    );
END_IF

bHomed := bHomeDone;

// ---------------------------------------------------------------------------
// Absolute Move — Primary motion command for shelf layer positioning
// ---------------------------------------------------------------------------
// Positions the scanning head at a specific height:
//   rPosition = layerNumber × FloorHeight
//
// Uses S-curve profile when rJerk > 0 for smooth motion that prevents
// RFID read errors and camera blur during acceleration/deceleration.

rtMoveAbs(CLK := bMoveAbs);
fbMoveAbs(
    Axis            := stAxisRef,
    Execute         := rtMoveAbs.Q,
    Position        := rPosition,
    Velocity        := rVelocity,
    Acceleration    := rAcceleration,
    Deceleration    := rDeceleration,
    Jerk            := rJerk
);

// ---------------------------------------------------------------------------
// Relative Move — Fine position adjustment
// ---------------------------------------------------------------------------
// Used for small corrections when the shelf layer height varies slightly
// from the configured FloorHeight parameter.

rtMoveRel(CLK := bMoveRel);
fbMoveRel(
    Axis            := stAxisRef,
    Execute         := rtMoveRel.Q,
    Distance        := rDistance,
    Velocity        := rVelocity,
    Acceleration    := rAcceleration,
    Deceleration    := rDeceleration,
    Jerk            := rJerk
);

// ---------------------------------------------------------------------------
// Velocity Move — Continuous scanning mode
// ---------------------------------------------------------------------------
// Moves at constant velocity for continuous scanning scenarios where the
// RFID reader operates in streaming mode rather than layer-by-layer.

rtMoveVel(CLK := bMoveVel);
fbMoveVel(
    Axis            := stAxisRef,
    Execute         := rtMoveVel.Q,
    Velocity        := rVelocity,
    Acceleration    := rAcceleration,
    Deceleration    := rDeceleration,
    Jerk            := rJerk
);

// ---------------------------------------------------------------------------
// Jog — Manual operator control
// ---------------------------------------------------------------------------
// Level-triggered: axis moves as long as button is held.
// Used during maintenance, calibration, and setup.

fbJog(
    Axis            := stAxisRef,
    JogForward      := bJogPos,
    JogBackward     := bJogNeg,
    Velocity        := rJogVelocity,
    Acceleration    := rAcceleration,
    Deceleration    := rDeceleration
);

// ---------------------------------------------------------------------------
// Halt & Stop
// ---------------------------------------------------------------------------
// MC_Halt: Controlled deceleration to standstill. Axis remains enabled.
// MC_Stop: Emergency trajectory abort. Axis goes to StandStill state and
//          rejects all new motion commands until Stop.Done.

fbHalt(
    Axis            := stAxisRef,
    Execute         := bHalt
);

fbStop(
    Axis            := stAxisRef,
    Execute         := bStop,
    Deceleration    := rDeceleration * 2.0  // Double decel for emergency
);

// ---------------------------------------------------------------------------
// Fault Reset
// ---------------------------------------------------------------------------
// Clears the drive error register (DS402 Fault → Switch On Disabled)
// and re-enables the axis. Homing is required after reset if the position
// reference may have been lost.

rtReset(CLK := bReset);
fbReset(
    Axis            := stAxisRef,
    Execute         := rtReset.Q
);

IF fbReset.Done THEN
    bHomeDone := FALSE;  // Force re-homing after fault recovery
END_IF

// ---------------------------------------------------------------------------
// Status Outputs
// ---------------------------------------------------------------------------
bMoving     := fbMoveAbs.Busy OR fbMoveRel.Busy OR fbMoveVel.Busy
               OR fbJog.Busy OR fbHome.Busy;
bInPosition := fbMoveAbs.Done OR fbMoveRel.Done;
bError      := fbPower.Error OR fbMoveAbs.Error OR fbHome.Error
               OR fbMoveRel.Error OR fbMoveVel.Error;
nErrorID    := fbPower.ErrorID;

rActPosition := stAxisRef.fSetPosition;  // From SoftMotion axis state
rActVelocity := stAxisRef.fSetVelocity;
