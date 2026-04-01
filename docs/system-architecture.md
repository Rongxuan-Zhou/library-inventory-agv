# System Architecture

## 1. Hardware Platform

### 1.1 PLC Controller

| Parameter | Specification |
|-----------|--------------|
| Runtime | CODESYS Control for Linux SL V4.6.0.0 |
| OS | Linux (embedded industrial PC) |
| IP Address | 192.168.100.101 |
| IDE Version | CODESYS V3.5 SP17+ |
| Motion Library | SoftMotion V4.15 (29 libraries) |

### 1.2 Stepper Drives

| Parameter | Specification |
|-----------|--------------|
| Manufacturer | Xinje Electric Co., Ltd. (信捷电气) |
| Model | XINJE DP3C(L) EtherCAT CoE Drive Rev2.1 |
| Type | **Closed-loop stepper driver** (not AC servo) |
| Protocol | EtherCAT CoE (CAN over EtherCAT) |
| Product Code | 0x30305070 |
| Firmware | v1.2.21 |
| Quantity | 2 units |
| Typical Motors | NEMA 17/23/34 (42/57/86mm) steppers with encoder feedback |

### 1.3 I/O System

- **EtherCAT I/O Terminals**: 8 modules (digital/analog I/O, likely Beckhoff EL series)
- **Modbus TCP Remote I/O**: 1 module (emergency stop, axis enable, status lights)
- **AoE (ADS over EtherCAT)**: Used for extended terminal configuration

### 1.4 Sensors

| Sensor | Connection | Status Variable |
|--------|-----------|-----------------|
| RFID Reader/Writer | TCP Socket | `HMI_RFID_ConnectionActive` |
| Machine Vision Camera | TCP Socket | `HMI_Vision_ConnectionActive` |
| Scanning Mechanism | TCP Socket | `HMI_AGVROB_ConnectionActive` |

## 2. Network Architecture

### 2.1 IP Address Allocation

| Device | IP Address | Protocol | Role |
|--------|-----------|----------|------|
| CODESYS PLC | 192.168.100.101 | EtherCAT Master, Modbus Master, HTTP/TCP Client | Main controller |
| Navigation System | 192.168.3.100:7000 | HTTP REST + WebSocket Server | SLAM, path planning, chassis control |
| Node-RED Data Store | 10.10.3.1:1880 | HTTP Server | Inventory data persistence |
| EtherCAT Network | 10.10.4.1 | EtherCAT | Real-time fieldbus |
| Modbus I/O Module | Via Modbus TCP | Modbus TCP Slave | Remote digital I/O |

### 2.2 Communication Protocol Matrix

| Source | Destination | Protocol | Cycle/Latency | Purpose |
|--------|------------|----------|---------------|---------|
| PLC → Stepper Drives | EtherCAT CSP | 1ms (DC-Sync) | Real-time position commands |
| PLC → I/O Terminals | EtherCAT | 1ms | Digital/analog I/O |
| PLC → Modbus I/O | Modbus TCP | ~10ms | E-Stop, axis enable, lights |
| PLC ↔ Navigation | HTTP REST | ~100ms | Task commands, status queries |
| PLC ↔ Navigation | WebSocket | Real-time push | Live status updates |
| PLC ↔ RFID Reader | TCP Socket | On-demand | Scan triggers, tag data |
| PLC ↔ Vision Camera | TCP Socket | On-demand | Capture triggers, results |
| PLC → Node-RED | HTTP POST | On-demand | Inventory data upload |

## 3. Software Architecture

### 3.1 PLC Task Configuration

| Task | Estimated Cycle | Priority | Responsibility |
|------|----------------|----------|----------------|
| **EtherCAT_Task** | 1ms | Highest | EtherCAT bus communication, PDO exchange, SoftMotion axis control |
| **MainTask** | ~10ms | Medium | AGV state machine, HTTP API calls, inventory logic, sensor coordination |
| **Stasu_Task** | ~100ms | Low-Medium | Periodic status reporting (StatusPost) |
| **VISU_TASK** | ~50ms | Lowest | Web HMI rendering and user input processing |

### 3.2 Global Variable Lists (GVL)

| GVL | Purpose | Key Contents |
|-----|---------|-------------|
| `GVL_Main` | Core control logic | State machine variables, task flow control |
| `GVL_HMI` | Human-machine interface | 67 HMI-bound variables (buttons, indicators, parameters) |
| `GVL_Servo` | Axis configuration | Velocity/acceleration limits, axis references |
| `GVL_Modbus_IO` | Modbus I/O mapping | E-Stop, axis enable, lighting controls |
| `GVL_TCP_IP` | TCP communication | Connection handles, send/receive buffers |
| `GVL_HostSys` | Host system interface | Navigation commands, system status |
| `GVL_Constant` | Fixed parameters | FloorHeight, shelf dimensions, timing constants |
| `GVL_hidden` | Internal/debug | Licensing, diagnostic variables |
| `GVL_CommandManager` | Command queuing | HTTP/TCP command dispatch |
| `GVL_Events` | Event management | Alarms, logging events |
| `GVL_ShutdownCheck` | Power-loss protection | Graceful shutdown for Linux SL |
| `GVL_ETC_AoE` | EtherCAT AoE | ADS communication parameters |
| `GVL_AoE_Counter` | AoE statistics | Communication counters |

### 3.3 Program Organization Units (37 User-Defined)

#### Motion Control Layer (7 POUs)

| POU | Type | Purpose |
|-----|------|---------|
| `A00_AxisETC` | PRG | EtherCAT axis object initialization (AXIS_REF_ETC_DS402_CS) |
| `A00_PointerAssignment` | PRG | Axis pointer assignment to global references |
| `A01_AxisOutputETC` | PRG | Axis output PDO mapping |
| `A01_Control` | PRG | **Core motion control** — MC_* function block orchestration |
| `A01_FBCall` | PRG | Function block instance calls with edge detection (RT/FT) |
| `A02_AxisResetETC` | PRG | Axis fault reset procedure |
| `AxisControl_FB` | FB | Encapsulated axis control function block |

#### AGV State Machine Layer (9 POUs)

| POU | Type | Purpose |
|-----|------|---------|
| `AgvControl_FB` | FB | **Master AGV state machine** — top-level task dispatcher |
| `AGV_MoveControl` | PRG/FB | Autonomous navigation execution |
| `AGV_MoveControlM` | PRG/FB | Manual movement mode |
| `AgvControlHome_FB` | FB | Homing/return-to-origin sequence |
| `AgvControlCharging_FB` | FB | Charging workflow (dock → charge → undock) |
| `AGV_chargingControl` | PRG | Charging logic upper layer |
| `AgvCharging_FB` | FB | Charging sub-process |
| `AgvDockingCance_FB` | FB | Docking cancellation handler |
| `AgvnavigatingCance_FB` | FB | Navigation cancellation handler |

#### Communication Layer (12 POUs)

| POU | Type | Purpose |
|-----|------|---------|
| `api_navigatting_start` | FB | Send navigation start request |
| `api_navigatting_staus` | FB | Query navigation status |
| `api_navigatting_Post` | FB | Send navigation POST request |
| `api_navigatting_docking` | FB | Charging station docking API |
| `api_navigatting_Undocking` | FB | Charging station undocking API |
| `api_DataTransReq` | FB | Data transfer request (→ RFID/Vision) |
| `api_DataTransRec` | FB | Data transfer receive |
| `StatusPost` | FB | Status report uploader |
| `Stasu_Task` | PRG | Periodic status reporting task |
| `TCP_Client` / `TCP_Server` | FB | TCP socket communication |
| `Tcp_Send` / `TCP_Read` | FB | TCP data send/receive |
| `Tcp_Master` | FB | TCP connection manager |

#### Data Structures & Utilities (5 POUs)

| POU | Type | Purpose |
|-----|------|---------|
| `AgvPointsInfor` | FB/PRG | Navigation waypoint management |
| `St_PointAxis` | DUT (Struct) | Waypoint data structure (name, x, y, angle, axis position) |
| `FB_Template_Edge` | FB | Rising/falling edge detection template |
| `FB_Template_EdgeAbort` | FB | Edge detection with abort capability |
| `FB_Template_EdgeAbortTimeout` | FB | Edge detection with abort + timeout |

### 3.4 Library Dependencies

The project uses **179 compiled libraries** (127 MB). Key library categories:

| Category | Libraries | Purpose |
|----------|-----------|---------|
| SoftMotion | 29 libraries (SM3_*) | Motion control, trajectory planning, robotics |
| EtherCAT | EtherCAT Master, IoDriver | Real-time fieldbus communication |
| Modbus | Modbus TCP Master/Slave | Remote I/O |
| Communication | TCP, CommFB, Web Client SL, WebSocket | Network protocols |
| JSON | JSON Utilities SL | REST API body construction |
| Visualization | VisuElem*, DefaultImages | Web HMI rendering |
| System | Standard, CmpApp, SysFile, etc. | Core PLC runtime |

## 4. System Startup & Initialization Sequence

Understanding the cold-start sequence is critical for commissioning and debugging initialization failures.

```
Power On
    │
    ▼
┌─────────────────────────────────┐
│ 1. Linux SL Boot (~10-30s)      │
│    - Linux kernel starts        │
│    - CODESYS runtime loads      │
│    - Persistent variables read  │
│      from flash (GVL_Shutdown)  │
└──────────┬──────────────────────┘
           ▼
┌─────────────────────────────────┐
│ 2. EtherCAT State Machine       │
│    Init → Pre-Op → Safe-Op → Op│
│                                 │
│    Pre-Op → Safe-Op:            │
│      SDO InitCmds sent:        │
│        0x6060=0x08 (CSP mode)  │
│        0x60C2=1ms interpolation│
│                                 │
│    Safe-Op → Op:                │
│      PDO exchange begins (1ms) │
│      DC sync established        │
│      All 10 slaves must be Op  │
└──────────┬──────────────────────┘
           ▼
┌─────────────────────────────────┐
│ 3. A00_AxisETC                  │
│    - Creates AXIS_REF_ETC_      │
│      DS402_CS objects           │
│    - Links axis to EtherCAT     │
│      slave device node          │
│                                 │
│ 4. A00_PointerAssignment        │
│    - Maps axis objects to       │
│      GVL_Servo.stAxis01/02      │
│    - Enables axis access from   │
│      any POU via global refs    │
└──────────┬──────────────────────┘
           ▼
┌─────────────────────────────────┐
│ 5. MainTask starts cycling      │
│    - GVL_Main initialized       │
│    - TCP connections opened     │
│      to RFID, Vision, AgvRob   │
│    - HTTP client initialized    │
│    - Modbus TCP channel active  │
│                                 │
│ 6. VISU_TASK starts             │
│    - Web HMI available at       │
│      http://<PLC_IP>:8080       │
└──────────┬──────────────────────┘
           ▼
┌─────────────────────────────────┐
│ 7. AGV State Machine → IDLE     │
│    - Axes NOT powered yet       │
│    - Operator must press        │
│      HMI_init_PB to complete    │
│      initialization             │
│    - Init checks:               │
│      ✓ EtherCAT OP state       │
│      ✓ E-Stop released          │
│      ✓ RFID/Vision connected   │
│    - Then: MC_Power → Homing   │
│    - HMI_EStopOK_LP turns on   │
└─────────────────────────────────┘
```

### 4.1 Prerequisites for Building/Opening the Project

| Component | Version | License Required |
|-----------|---------|-----------------|
| CODESYS IDE | V3.5 SP17+ (SP18 recommended) | Free (IDE itself) |
| CODESYS Control for Linux SL | V4.6.0.0 | **Yes** — runtime license per device |
| SoftMotion | V4.15 | **Yes** — licensed add-on |
| EtherCAT Master | V4.6.0.0 | Included with runtime |
| Web Client SL | V1.9.0.0 | **Yes** — licensed add-on |
| JSON Utilities SL | V1.9.0.0 | **Yes** — licensed add-on |
| Visualization (WebVisu) | V4.4.0.0 | Included with runtime |

> **For portfolio review only**: The CODESYS IDE is free to download. Opening the project to view code and configurations does not require any runtime license. Licenses are only needed for deploying to a physical target.

## 5. XINJE DP3C(L) Common Error Codes

The drive reports errors via DS402 object 0x603F (Error Code) in the TxPDO. Common codes:

| Error Code | Category | Description | Typical Cause | Recovery |
|------------|----------|-------------|---------------|----------|
| 0x2310 | Overcurrent | Continuous overcurrent | Motor wiring fault, load jam | Check wiring, clear obstruction, MC_Reset |
| 0x2320 | Short circuit | Output short circuit | Cable damage, connector failure | Inspect cables, replace if damaged |
| 0x3110 | Overvoltage | DC bus overvoltage | Regen during fast decel, PSU issue | Reduce decel rate, check brake resistor |
| 0x3120 | Undervoltage | DC bus undervoltage | Power supply dip, breaker trip | Check PSU, verify power circuit |
| 0x4210 | Overtemperature | Drive overheating | Insufficient cooling, overload | Reduce duty cycle, improve ventilation |
| 0x5113 | Logic error | Internal firmware error | Firmware bug or corruption | Power cycle, update firmware |
| 0x7121 | Motor blocked | Motor stall detected | Mechanical jam, belt slip | Clear obstruction, check coupling |
| 0x7300 | Sensor | Encoder error | Encoder cable fault, noise | Check encoder wiring, shield cables |
| 0x7380 | Sensor | Encoder signal loss | Encoder disconnected | Re-seat encoder connector |
| 0x8611 | Following error | Position lag exceeded | Load too heavy, accel too high, jam | Tune fMaxPositionLag, reduce dynamics |
| 0xFF01 | Homing error | Homing not completed | Home switch not reached | Check switch, verify travel range |
| 0xFF02 | Homing error | Homing timeout | Homing speed too slow for range | Increase homing velocity |

> These codes are based on the CiA 402 standard error code structure. The XINJE DP3C-L manual may define additional vendor-specific codes in the 0xFF00-0xFFFF range.
