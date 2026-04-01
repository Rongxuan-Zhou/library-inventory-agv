# Safety Design

## 1. Emergency Stop Architecture

### 1.1 E-Stop Signal Path

```
Physical E-Stop Button
        │
        ▼
┌───────────────────┐
│ Safety Relay       │  ← Hardwired Category 1 stop (IEC 60204-1)
│ (hardware circuit) │     Directly cuts motor power
└───────┬───────────┘
        │
        ▼ (status mirror)
┌───────────────────┐
│ Modbus TCP I/O     │  ← Software status feedback ONLY
│ modbus_E_Stop      │     NOT the primary safety channel
└───────┬───────────┘
        │
        ▼
┌───────────────────┐
│ CODESYS PLC        │  ← Reads E-Stop state for:
│ HMI_EStopOK_LP    │     • HMI indicator display
│                    │     • State machine transition to ERROR
│                    │     • Logging and diagnostics
└───────────────────┘
```

> **Design Note**: The Modbus TCP `modbus_E_Stop` signal is a **status mirror** for HMI display and logging. The primary safety action (motor power cutoff) is performed by the hardwired safety relay circuit, which operates independently of the PLC and communication networks.

### 1.2 Software Safety Layers

```
Layer 1: Drive-Level Protection (XINJE DP3C)
  ├── Hardware overcurrent protection
  ├── Encoder feedback loss detection
  ├── Stall detection (closed-loop stepper)
  └── Reports via DS402 Statusword (0x6041) + Error Code (0x603F)

Layer 2: SoftMotion Axis Protection
  ├── fMaxPositionLag → Following error monitoring
  │   (triggers alarm if actual position deviates from commanded)
  ├── fMaxVelocity → Software velocity limit
  ├── fMaxAcceleration / fMaxDeceleration → Dynamic limits
  ├── fMaxTorque / fMaxCurrent → Force limits
  └── Software limit switches (MC_WriteBoolParameter)

Layer 3: PLC Application Logic
  ├── E-Stop monitoring (modbus_E_Stop)
  ├── MC_Stop on any communication loss
  ├── State machine error handling
  └── GVL_ShutdownCheck → Graceful shutdown on power loss

Layer 4: HMI Operator Controls
  ├── HMI_EStopOK_LP → Visual E-Stop status
  ├── HMI_Rest_PB → Manual fault reset
  ├── HMI_DockingCancel → Abort docking
  └── HMI_NavigatingCancel → Abort navigation
```

## 2. Fault Handling

### 2.1 Axis Fault Recovery Sequence

```
Fault Detected (axis ErrorStop state)
    │
    ├── MC_Stop_ETC(Execute := TRUE)
    │   → Ensure controlled stop of all motion
    │
    ├── Display on HMI
    │   → HMI_Ax01_Fault / HMI_Ax02_Fault := TRUE
    │
    ├── Operator presses HMI_Rest_PB
    │   │
    │   ├── MC_Reset_ETC(Execute := TRUE)
    │   │   → Clear drive fault register
    │   │   → DS402: Fault → Switch On Disabled
    │   │
    │   ├── MC_Power_ETC(Enable := TRUE)
    │   │   → Re-enable drive
    │   │   → DS402: Switch On Disabled → Operation Enabled
    │   │
    │   └── MC_Home_ETC(Execute := TRUE)
    │       → Re-establish position reference
    │       → Required after any fault that may affect encoder position
    │
    └── Resume operation
```

### 2.2 Communication Failure Handling

| Failure | Detection | Response |
|---------|-----------|----------|
| EtherCAT bus loss | Bus cycle monitoring (EtherCAT_Task) | MC_Stop → all axes ErrorStop |
| Navigation API timeout | HTTP response timeout | Hold position, retry 3×, then ErrorStop |
| RFID connection lost | `HMI_RFID_ConnectionActive = FALSE` | Pause scanning, wait for reconnect |
| Vision connection lost | `HMI_Vision_ConnectionActive = FALSE` | Pause scanning, log warning |
| Modbus TCP timeout | Modbus driver diagnostics | Fallback to safe I/O state |

### 2.3 Position Lag Monitoring

```
fMaxPositionLag defines the maximum allowed deviation between:
  - Commanded position (from SoftMotion trajectory planner)
  - Actual position (from encoder feedback via 0x6064)

If |commanded - actual| > fMaxPositionLag:
  → Axis immediately enters ErrorStop
  → Prevents mechanical damage from:
    • Mechanical obstruction (someone's hand in the mechanism)
    • Belt/coupling failure
    • Motor stall
    • Encoder malfunction
```

## 3. Battery Management & Charging Safety

### 3.1 Battery Monitoring

```
Battery level source: Navigation system API
  → api_navigatting_BATTERY_BASE_STATUS
  → Returned via HTTP response JSON or WebSocket push
  → Stored in: HMI_AGVbBttery (REAL, 0-100%)

Threshold logic (in AgvControl_FB):
  IF rBatteryLevel < C_BATTERY_LOW (20%) THEN
      eState := AGV_GO_CHARGING;
  END_IF
```

### 3.2 Charging Sequence

```
AgvControlCharging_FB manages:
  1. Navigate to charging station → api/navigating/charging_station/docking
  2. Physical connector engagement (handled by navigation system)
  3. Start charging → POST /api/charging/start
  4. Monitor until full (polled via StatusPost or WebSocket)
  5. Stop charging → POST /api/charging/stop
  6. Undock → POST /api/navigating/charging_station/undocking
  7. Resume interrupted inventory task
```

### 3.3 Charging Safety

- Charging only initiated when AGV is stationary and docked (not during motion)
- If charging station is occupied or unreachable, AGV holds position and retries
- Low-battery threshold (20%) provides sufficient reserve for navigation to charger
- Critical-low threshold (if implemented) would trigger immediate MC_Halt + hold

## 4. Operational Safety for Library Environment

### 3.1 Public Space Considerations

Operating in a library presents unique safety requirements beyond typical industrial environments:

| Concern | Mitigation |
|---------|-----------|
| Patron proximity | Low maximum velocity limits; controlled S-curve acceleration to avoid sudden movements |
| Noise | Stepper drives at low speed are quieter than AC servos; velocity limits reduce mechanical noise |
| Collision risk | Navigation system handles obstacle avoidance; PLC monitors E-Stop for emergency situations |
| Pinch hazard (lifting axis) | Position lag monitoring detects obstruction; mechanical guards on linear guide |
| Power failure during scan | `GVL_ShutdownCheck` enables graceful shutdown; Linux SL supports UPS monitoring |

### 3.2 GVL_ShutdownCheck — Power Loss Protection

```
Linux SL specific feature:
  - Monitors system power state
  - On power loss detection:
    1. Save current scan position and progress
    2. MC_Halt on all axes (controlled deceleration)
    3. Write persistent variables to flash/disk
    4. After power restore: resume from saved state
```
