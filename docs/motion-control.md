# Motion Control Design

## 1. Drive System: XINJE DP3C(L) Closed-Loop Stepper

### 1.1 Why Closed-Loop Stepper (Not AC Servo)

For a library inventory AGV's vertical scanning axis, closed-loop stepper drives offer:

- **High torque at low speed**: The scanning mechanism moves slowly between shelf layers (~200-500 mm/s). Steppers excel in this regime without the cogging typical of servo motors.
- **Sufficient positioning accuracy**: With encoder feedback, closed-loop steppers achieve ±0.05mm repeatability — more than adequate for shelf-layer alignment.
- **Cost-effectiveness**: ~40% lower cost than comparable AC servo systems for similar torque requirements.
- **Stall detection**: Closed-loop feedback prevents missed steps, critical for vertical (gravity-loaded) axes.

### 1.2 Operating Mode: Cyclic Synchronous Position (CSP)

The drive is initialized to **DS402 Op Mode 0x08 (CSP)** via SDO during the Pre-Operational → Safe-Operational transition:

```
InitCmd #1: Index 0x6060, SubIndex 0, Data = 0x08  → CSP mode
InitCmd #2: Index 0x60C2:1, Data = 0x01            → Interpolation period = 1
InitCmd #3: Index 0x60C2:2, Data = 0xFD (-3)       → Time index = 10^(-3) = 1ms
```

**CSP mode characteristics:**
- PLC computes a new target position every 1ms EtherCAT cycle
- Drive performs position loop closure internally at higher frequency
- Enables smooth S-curve trajectory following
- Better path accuracy than Profile Position (PP) mode for continuous scanning motions

### 1.3 DS402 State Machine

```
                        ┌──────────────────┐
                        │  Not Ready to    │
                        │  Switch On       │  (Power-on, self-test)
                        └────────┬─────────┘
                                 │ automatic
                        ┌────────▼─────────┐
                        │  Switch On       │
                        │  Disabled        │  (Drive initialized)
                        └────────┬─────────┘
                                 │ CW bits 1,2 = 1
                        ┌────────▼─────────┐
                        │  Ready to        │
                        │  Switch On       │  (Parameters loaded)
                        └────────┬─────────┘
                                 │ CW bit 0 = 1
                        ┌────────▼─────────┐
                        │  Switched On     │  (Motor energized, no motion)
                        └────────┬─────────┘
                                 │ CW bit 3 = 1 (MC_Power)
                        ┌────────▼─────────┐
                        │  Operation       │  ← Normal running state
                        │  Enabled         │    PLC updates TargetPosition
                        └────────┬─────────┘    every 1ms cycle
                                 │ Fault condition
                        ┌────────▼─────────┐
                        │  Fault           │  → MC_Reset to recover
                        └──────────────────┘

CW = Controlword (0x6040)
```

## 2. PDO Mapping

### 2.1 RxPDO (PLC → Drive, 1600h, every 1ms)

| Index | SubIndex | Name | Type | Size | Description |
|-------|----------|------|------|------|-------------|
| 0x6040 | 0 | Controlword | UINT | 16-bit | DS402 state machine control |
| 0x607A | 0 | Target Position | DINT | 32-bit | Position setpoint (encoder counts) |
| 0x60B8 | 0 | Touch Probe Function | UINT | 16-bit | Home switch / probe trigger |

### 2.2 TxPDO (Drive → PLC, 1A00h, every 1ms)

| Index | SubIndex | Name | Type | Size | Description |
|-------|----------|------|------|------|-------------|
| 0x603F | 0 | Error Code | UINT | 16-bit | Drive fault code |
| 0x6041 | 0 | Statusword | UINT | 16-bit | DS402 state feedback |
| 0x6061 | 0 | Modes of Operation display | SINT | 8-bit | Active operating mode |
| 0x6064 | 0 | Position Actual Value | DINT | 32-bit | Current position (encoder counts) |
| 0x60B9 | 0 | Touch Probe Status | UINT | 16-bit | Probe/home switch state |

### 2.3 Synchronization

- **Mode**: Distributed Clock (DC-Sync)
- **AssignActivate**: 0x300
- **CycleTimeSync0**: Matched to EtherCAT task cycle (1ms)

## 3. SoftMotion Configuration

### 3.1 Axis Reference Types

| Type | Usage |
|------|-------|
| `AXIS_REF_ETC_DS402_CS` | EtherCAT axis with DS402 Cyclic Sync — **primary type used** |
| `AXIS_REF_ETC_SM3` | EtherCAT axis base reference |
| `AXIS_REF_ETC_BASE_SM3` | Base EtherCAT axis class |
| `AXIS_REF_MAPPING_SM3` | Axis mapping reference |
| `AXIS_REF_VIRTUAL_SM3` | Virtual axis (for simulation/testing) |

### 3.2 PLCopen MC_ Function Blocks Used (15)

| Function Block | Purpose | Typical Usage in This Project |
|---------------|---------|-------------------------------|
| `MC_Power_ETC` | Enable/disable axis | Drive enable at startup, disable at shutdown |
| `MC_Home_ETC` | Execute homing sequence | Find mechanical zero after power-on |
| `MC_MoveAbsolute_ETC` | Move to absolute position | **Primary**: Move to specific shelf layer |
| `MC_MoveRelative_ETC` | Move by relative distance | Fine-tune layer position |
| `MC_MoveVelocity_ETC` | Continuous velocity motion | Constant-speed scanning mode |
| `MC_MoveAdditive_ETC` | Add distance to current motion | Position compensation |
| `MC_Jog_ETC` | Manual jog forward/backward | Maintenance/setup mode |
| `MC_Halt_ETC` | Controlled deceleration stop | Normal stop during operation |
| `MC_Stop_ETC` | Emergency trajectory abort | Safety stop |
| `MC_Reset_ETC` | Clear axis fault | Fault recovery |
| `MC_SetPosition_ETC` | Set encoder position value | Calibrate after homing |
| `MC_ReadParameter` | Read axis parameter | Runtime parameter monitoring |
| `MC_WriteParameter` | Write axis parameter | Runtime parameter adjustment |
| `MC_ReadBoolParameter` | Read boolean axis parameter | Check limit switch states |
| `MC_WriteBoolParameter` | Write boolean axis parameter | Enable/disable software limits |

### 3.3 Trajectory Planning Parameters

| Parameter | Variable | Default | Unit | Purpose |
|-----------|----------|---------|------|---------|
| Max velocity | `fMaxVelocity` | 500.0 | mm/s | Upper speed limit for axis travel |
| Max acceleration | `fMaxAcceleration` | 800.0 | mm/s² | Ramp-up rate limit |
| Max deceleration | `fMaxDeceleration` | 800.0 | mm/s² | Ramp-down rate limit |
| Max jerk | `fMaxJerk` | 3000.0 | mm/s³ | S-curve smoothness; set 0 for trapezoidal |
| Max position lag | `fMaxPositionLag` | 5.0 | mm | Following error alarm threshold (safety-critical) |
| Cruise velocity | `fMaxVelKeep` | 300.0 | mm/s | Constant velocity during steady-state travel |
| Direction-change vel | `fMaxVelTurn` | 100.0 | mm/s | Speed during reversal (up→down transition) |
| Max torque | `fMaxTorque` | 3.0 | Nm | Stepper motor rated torque |
| Max current | `fMaxCurrent` | 5.0 | A | Drive current limit |

> **Tuning note for vertical axis**: `fMaxPositionLag` is safety-critical on a gravity-loaded vertical axis. Too loose (>10mm) may allow the carriage to drop before the alarm triggers. Too tight (<1mm) causes nuisance faults during normal S-curve acceleration. The default of 5.0mm is a conservative starting point; tune by observing the actual following error during maximum-speed moves and setting the threshold at ~2× the observed peak.

### 3.4 Ramp Types Available

SoftMotion provides three acceleration profile types:

| Profile | Code | Characteristics | Use Case |
|---------|------|-----------------|----------|
| Trapezoidal | `smc_trapezoid` | Constant acceleration, abrupt jerk | Basic positioning |
| Quadratic | `smc_quadratic` | Smooth acceleration curve | General motion |
| Sine-squared | `smc_sinsquare_vel_ramp` | **Smoothest** — minimal vibration | **Preferred for scanning** to avoid camera blur and RFID read errors |

### 3.5 Homing Procedure

Homing establishes the absolute position reference for the vertical lift axis. Without a successful homing sequence, the axis cannot perform accurate absolute positioning to shelf layers.

#### Homing Method

The XINJE DP3C supports DS402 standard homing methods configured via SDO 0x6098. Based on the project's use of Touch Probe (0x60B8/0x60B9 in the PDO mapping), the most likely configuration is:

| SDO Object | Value | Meaning |
|------------|-------|---------|
| 0x6098 (Homing Method) | 1 or 2 | Homing on negative/positive limit switch + index pulse |
| 0x6099:1 (Speed during search for switch) | ~100 mm/s | Fast approach to home switch |
| 0x6099:2 (Speed during search for index) | ~20 mm/s | Slow crawl to encoder index after switch |

#### Homing Sequence in ST

```iecst
// Homing is a multi-step process:
// 1. Axis moves toward home switch at fast speed
// 2. Home switch triggers → axis reverses at slow speed
// 3. Encoder index pulse detected → position reference established
// 4. MC_SetPosition sets current position to 0.0 mm

fbHome(
    Axis    := GVL_Servo.stAxis01,
    Execute := bStartHoming        // Rising edge triggers
);

// Monitor homing state
CASE nHomingStep OF
0:  // Start
    IF bStartHoming THEN
        fbHome.Execute := TRUE;
        nHomingStep := 1;
    END_IF

1:  // Wait for completion
    IF fbHome.Done THEN
        // Homing successful — set position to 0
        fbSetPos(
            Axis     := GVL_Servo.stAxis01,
            Execute  := TRUE,
            Position := 0.0
        );
        nHomingStep := 2;
    ELSIF fbHome.Error THEN
        // Homing failed — common causes:
        //   - Home switch not reached within travel range
        //   - Encoder index pulse not found
        //   - Drive fault during homing motion
        nHomingErrorID := fbHome.ErrorID;
        nHomingStep := 99;  // Error
    END_IF

2:  // Position set
    IF fbSetPos.Done THEN
        bHomingComplete := TRUE;
        nHomingStep := 0;
    END_IF

99: // Error — requires operator intervention
    // Display nHomingErrorID on HMI
    // Operator must resolve mechanical issue, then reset + re-home
END_CASE
```

#### Safety Constraints During Homing

- The homing speed is limited to prevent mechanical damage if the home switch fails
- `fMaxPositionLag` monitoring remains active during homing — a stall triggers ErrorStop
- If homing is interrupted (E-Stop, fault), the axis position reference is marked invalid and all `MC_MoveAbsolute` commands are rejected until re-homing

### 3.6 Axis 02 — Function and Configuration

> **Note**: The exact mechanical function of Axis 02 is not fully documented in the project. Based on the code structure (separate preset positions, independent homing, independent jog controls), the most likely candidates are:
>
> - **Horizontal traverse**: A short-stroke linear axis that extends the scanning head toward/away from the bookshelf for optimal RFID read distance
> - **Second vertical axis**: A second independent scanning column (for scanning both sides of a double-sided shelf unit)
> - **Tilt adjustment**: Angular positioning of the RFID antenna array
>
> Axis 02 shares the same XINJE DP3C(L) drive type and CSP operating mode as Axis 01.

| Property | Axis 01 | Axis 02 |
|----------|---------|---------|
| Drive | XINJE DP3C(L) @ Slot 170 | XINJE DP3C(L) @ Slot 160 |
| Preset P01 | Bottom (home) | Retracted / Home |
| Preset P02 | Top (full travel) | Extended / Max travel |
| Primary MC_ | MC_MoveAbsolute | MC_MoveAbsolute |
| HMI Jog | HMI_Ax02_JogP/N_PB | HMI_Ax02_JogP/N_PB |

### 3.7 Motion Sequence for Layer Scanning

```
Step 1: MC_Power(Enable := TRUE)
        → Axis enters "Operation Enabled" state

Step 2: MC_Home(Execute := TRUE)
        → Axis finds mechanical zero (home switch + encoder index)
        → MC_SetPosition to calibrate encoder zero point

Step 3: FOR layer := LowerStartLayerNumber TO UpperStartLayerNumber DO

          targetPosition := layer × FloorHeight;

          MC_MoveAbsolute(
              Position     := targetPosition,
              Velocity     := fMaxVelocity,
              Acceleration := fMaxAcceleration,
              Deceleration := fMaxDeceleration,
              Jerk         := fMaxJerk     // S-curve
          );

          WAIT UNTIL InPosition;
          
          → Trigger RFID scan
          → Trigger vision capture
          → Wait for data
          
        END_FOR

Step 4: MC_MoveAbsolute(Position := 0)  // Return to home
Step 5: MC_Power(Enable := FALSE)        // If task complete
```

## 4. EtherCAT Bus Topology

See [EtherCAT Configuration](ethercat-configuration.md) for the complete bus topology diagram, slave addressing, and port groupings (HPS_0/1/2).

Summary: 10 EtherCAT slaves (2 XINJE DP3C stepper drives + 7 I/O terminals + 1 bus coupler), all running at 1ms cycle with Distributed Clock synchronization.

## 5. Modbus TCP I/O Mapping

| IoMap Address | Variable | Type | Direction | Purpose |
|--------------|----------|------|-----------|---------|
| 16,88145920,0,1 | `modbus_E_Stop` | BOOL | Input | Emergency stop status feedback |
| 16,42074113,0,1 | `modbus_Axi01_PowerOn` | BOOL | Output | Axis 01 servo enable |
| 16,25296896,0,1 | `modbus_Axi02_PowerOn` | BOOL | Output | Axis 02 servo enable |
| — | `modbus_Light01_PowerOn` | BOOL | Output | Warning light #1 |
| — | `modbus_Light02_PowerOn` | BOOL | Output | Warning light #2 |
