// =============================================================================
// GVL_Servo — Servo/Stepper Axis Configuration and Runtime Parameters
// =============================================================================

{attribute 'qualified_only'}
VAR_GLOBAL
    // =========================================================================
    // Axis References
    // =========================================================================
    // Physical EtherCAT axes connected to XINJE DP3C(L) drives.
    // AXIS_REF_ETC_DS402_CS provides the SoftMotion interface for
    // Cyclic Synchronous Position mode over EtherCAT.

    stAxis01        : AXIS_REF_ETC_DS402_CS;    // Vertical lift axis
    stAxis02        : AXIS_REF_ETC_DS402_CS;    // Secondary axis

    // =========================================================================
    // Dynamic Limits — Applied to all motion commands
    // =========================================================================

    // Velocity limits (mm/s)
    fMaxVelocity    : LREAL := 500.0;       // Maximum travel speed
    fMaxVelKeep     : LREAL := 300.0;       // Cruising speed during steady travel
    fMaxVelTurn     : LREAL := 100.0;       // Speed limit during direction reversal

    // Acceleration limits (mm/s²)
    fMaxAcceleration : LREAL := 800.0;      // Maximum acceleration
    fMaxDeceleration : LREAL := 800.0;      // Maximum deceleration

    // Jerk limit (mm/s³) — controls S-curve smoothness
    // Higher jerk = faster transition but more vibration
    // Lower jerk  = smoother but slower acceleration ramp
    fMaxJerk        : LREAL := 3000.0;

    // =========================================================================
    // Protection Limits
    // =========================================================================

    // Following error threshold (mm)
    // If |commanded_pos - actual_pos| exceeds this value, axis enters ErrorStop.
    // This detects: mechanical obstruction, belt slip, encoder fault, motor stall.
    fMaxPositionLag : LREAL := 5.0;

    // Force limits (drive-specific)
    fMaxTorque      : LREAL := 3.0;         // Nm (stepper rated torque)
    fMaxCurrent     : LREAL := 5.0;         // Amps (drive current limit)

    // =========================================================================
    // Preset Positions (mm)
    // =========================================================================
    // Quick-access positions for HMI jog/preset buttons.

    rAx01_PresetP01 : LREAL := 0.0;        // Bottom position (home)
    rAx01_PresetP02 : LREAL := 1800.0;     // Top position (full travel)
    rAx02_PresetP01 : LREAL := 0.0;
    rAx02_PresetP02 : LREAL := 1800.0;

    // =========================================================================
    // Jog Velocities (mm/s) — Operator-adjustable from HMI
    // =========================================================================
    fAx01_JogVel    : LREAL := 50.0;       // Default jog speed axis 1
    fAx02_JogVel    : LREAL := 50.0;       // Default jog speed axis 2

    // =========================================================================
    // Runtime Status (read-only from application code)
    // =========================================================================
    bAx01_Enabled   : BOOL;                // Axis 1 powered
    bAx01_Homed     : BOOL;                // Axis 1 homing complete
    bAx01_Moving    : BOOL;                // Axis 1 in motion
    bAx01_Error     : BOOL;                // Axis 1 fault active
    rAx01_ActPos    : LREAL;               // Axis 1 actual position (mm)
    rAx01_ActVel    : LREAL;               // Axis 1 actual velocity (mm/s)

    bAx02_Enabled   : BOOL;
    bAx02_Homed     : BOOL;
    bAx02_Moving    : BOOL;
    bAx02_Error     : BOOL;
    rAx02_ActPos    : LREAL;
    rAx02_ActVel    : LREAL;
END_VAR
