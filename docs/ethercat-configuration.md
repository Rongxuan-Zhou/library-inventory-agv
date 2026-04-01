# EtherCAT Configuration

## 1. Bus Overview

| Parameter | Value |
|-----------|-------|
| Master | CODESYS EtherCAT Master V4.6.0.0 |
| Cycle Time | 1ms |
| Synchronization | Distributed Clock (DC-Sync) |
| Total Slaves | 10 (+ 1 DPS device) |
| Drive Protocol | CiA 402 / DS402 |
| Drive Op Mode | CSP (Cyclic Synchronous Position) — 0x08 |

## 2. Slave Topology

```
EtherCAT Master
    │
    ├── Port 0 (HPS_0) ─── 2 devices
    │   ├── [170] XINJE DP3C(L) #1 — Vertical lift axis
    │   └── [160] XINJE DP3C(L) #2 — Secondary axis
    │
    ├── Port 1 (HPS_1) ─── 3 devices
    │   ├── [159] I/O Terminal — Digital inputs
    │   ├── [169] I/O Terminal — Digital outputs
    │   └── [161] I/O Terminal — Mixed I/O
    │
    ├── Port 2 (HPS_2) ─── 4 devices
    │   ├── [156] I/O Terminal
    │   ├── [157] I/O Terminal
    │   ├── [158] I/O Terminal
    │   └── [171] I/O Terminal
    │
    └── [DPS] [173] Bus Coupler / Gateway
```

## 3. XINJE DP3C(L) Drive Configuration

### 3.1 Device Identity

| Field | Value |
|-------|-------|
| Vendor | Xinje Electric Co., Ltd. |
| Product | XINJE-DP3C(L) CoE Drive Rev2.1 |
| Product Code | 0x30305070 |
| Revision | 0x20211108 |
| Type | Closed-loop stepper driver |
| Mailbox | CoE (SDO Info, PDO Assign, PDO Config) |
| MII Ports | 2 (daisy-chain capable) |

### 3.2 Initialization Commands (Pre-Op → Safe-Op)

| Step | Index | SubIndex | Data | Description |
|------|-------|----------|------|-------------|
| 1 | 0x6060 | 0 | 0x08 | Set operating mode to CSP |
| 2 | 0x60C2 | 1 | 0x01 | Interpolation time period value = 1 |
| 3 | 0x60C2 | 2 | 0xFD | Interpolation time index = -3 (10^-3 = 1ms) |

### 3.3 RxPDO Mapping (1600h — PLC → Drive)

4 RxPDO mappings available, primary mapping:

| Entry | Index | SubIndex | Bits | Type | Name |
|-------|-------|----------|------|------|------|
| 1 | 0x6040 | 0 | 16 | UINT | Controlword |
| 2 | 0x607A | 0 | 32 | DINT | Target Position |
| 3 | 0x60B8 | 0 | 16 | UINT | Touch Probe Function |

**Total RxPDO size: 8 bytes per cycle**

### 3.4 TxPDO Mapping (1A00h — Drive → PLC)

4 TxPDO mappings available, primary mapping:

| Entry | Index | SubIndex | Bits | Type | Name |
|-------|-------|----------|------|------|------|
| 1 | 0x603F | 0 | 16 | UINT | Error Code |
| 2 | 0x6041 | 0 | 16 | UINT | Statusword |
| 3 | 0x6061 | 0 | 8 | SINT | Modes of Operation Display |
| 4 | 0x6064 | 0 | 32 | DINT | Position Actual Value |
| 5 | 0x60B9 | 0 | 16 | UINT | Touch Probe Status |

**Total TxPDO size: 11 bytes per cycle** (may be padded to 12 bytes for DWORD alignment on the bus)

### 3.5 DS402 Object Dictionary (Used Objects)

| Index | Name | Access | Type | Description |
|-------|------|--------|------|-------------|
| 0x6040 | Controlword | RW | UINT | State machine control bits |
| 0x6041 | Statusword | RO | UINT | State machine status bits |
| 0x603F | Error Code | RO | UINT | Last error code |
| 0x6060 | Modes of Operation | RW | SINT | Requested operating mode |
| 0x6061 | Modes of Operation Display | RO | SINT | Active operating mode |
| 0x6064 | Position Actual Value | RO | DINT | Encoder position (counts) |
| 0x606C | Velocity Actual Value | RO | DINT | Current velocity |
| 0x607A | Target Position | RW | DINT | Position setpoint (CSP mode) |
| 0x6081 | Profile Velocity | RW | UDINT | Velocity for profile modes |
| 0x6098 | Homing Method | RW | SINT | Homing sequence type |
| 0x6099 | Homing Speeds | RW | UDINT[2] | Fast/slow homing velocities |
| 0x60B8 | Touch Probe Function | RW | UINT | Probe/home switch control |
| 0x60B9 | Touch Probe Status | RO | UINT | Probe/home switch state |
| 0x60C2 | Interpolation Time Period | RW | STRUCT | Cycle time configuration |
| 0x60FF | Target Velocity | RW | DINT | Velocity setpoint (CSV mode) |

### 3.6 DC Synchronization

```
OpMode: DC (DC-Synchron)
AssignActivate: 0x300
CycleTimeSync0: Matched to EtherCAT task (1ms)
CycleTimeSync1: Not used (single sync signal)
Unknown64Bit: true (extended timestamp support)
```

## 4. AoE (ADS over EtherCAT)

The project includes AoE communication capability for extended device configuration:

| GVL | Purpose |
|-----|---------|
| `GVL_ETC_AoE` | AoE communication parameters and command buffers |
| `GVL_AoE_Counter` | AoE transaction counters and diagnostics |

AoE enables:
- Reading/writing drive parameters not accessible via standard CoE SDO
- Diagnostic data collection from Beckhoff-compatible I/O terminals
- Runtime parameter monitoring without interrupting cyclic PDO communication

## 5. SoftMotion Library Stack (29 Libraries)

| Library | Version | Purpose |
|---------|---------|---------|
| SM3_Basic | 4.15.0.0 | Core MC_ function blocks |
| SM3_Drive_ETC | 4.15.0.0 | EtherCAT drive interface |
| SM3_Drive_ETC_DS402_CyclicSync | 4.14.0.0 | DS402 CSP mode implementation |
| SM3_Drive_CiA_DSP402 | 4.15.0.0 | CiA 402 state machine |
| SM3_TrajectoryGeneration | 4.13.0.0 | Trajectory planner (trapezoidal, S-curve) |
| SM3_Ramps | 4.14.0.0 | Acceleration profiles |
| SM3_AddRampsDefault | 4.14.0.0 | Default ramp configurations |
| SM3_Dynamics | 4.15.0.0 | Dynamic limit calculations |
| SM3_Math | 4.15.0.0 | Motion mathematics |
| SM3_Robotics | 4.15.0.0 | Robot kinematics |
| SM3_Transformation | 4.15.0.0 | Coordinate transformations |
| SM3_RBase | 4.15.0.0 | Robotics base library |
| SM3_RCP | 4.15.0.0 | Robot continuous path |
| SM3_CNC | 4.15.0.0 | CNC functionality |
| SM3_Error | 4.15.0.0 | Error handling |
| SM3_Shared | 4.15.0.0 | Shared data structures |
| SM3_ETC_ITF | 4.15.0.0 | EtherCAT interfaces |
| SM3_CommonPublic | 4.14.0.0 | Public interfaces |
| SM3_CPKernelDefaults | 4.15.0.0 | Continuous path defaults |
| SM3_Robotics_Visu | 4.15.0.0 | Robotics visualization |
| SM3_CNC_Visu | 4.14.0.0 | CNC visualization |
| SM3_Depictor | 4.15.0.0 | Motion visualization |
| SM3_Debug | 4.14.0.0 | Debug tools |
| SM3_Drive_PosControl | 4.15.0.0 | Position control |
| SM3_Drive_CAN | 4.15.0.0 | CAN drive interface |
| SM3_Drive_CAN_DS402_CyclicSync | 4.14.0.0 | CAN DS402 CSP |
| SM3_Drive_CAN_DS402_IP | 4.14.0.0 | CAN DS402 interpolated position |
| SM3_Drive_ETC_DS402_IP | 4.14.0.0 | EtherCAT DS402 interpolated position |
| SML_Basic | 4.15.0.0 | SoftMotion Lite base (lightweight subset, auto-included) |

> **Note on mixed versions**: Libraries at V4.14 (SM3_Ramps, SM3_Drive_ETC_DS402_CyclicSync, SM3_AddRampsDefault, etc.) were not updated to V4.15 because the SoftMotion V4.15 installer bundle ships these specific libraries at 4.14 as their latest stable release. This is the default CODESYS package manager resolution — not a manual downgrade. `SML_Basic` is the SoftMotion Lite runtime included automatically by the SoftMotion profile; it is not a separately licensed component.
