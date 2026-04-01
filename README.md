# Library Book Inventory AGV — Real-Time Motion Control System

> Autonomous guided vehicle for automated library bookshelf inventory using RFID + machine vision, built on CODESYS V3.5 with SoftMotion and EtherCAT fieldbus.

## Overview

This project implements the complete PLC control system for a library inventory AGV robot that autonomously navigates between bookshelves, positions a vertical scanning mechanism at each shelf layer, and reads book RFID tags combined with machine vision for stocktaking.

The system controls:
- **Dual-axis closed-loop stepper drives** (XINJE DP3C-L) via EtherCAT in Cyclic Synchronous Position (CSP) mode at 1ms cycle time
- **Multi-protocol communication**: EtherCAT real-time fieldbus, Modbus TCP I/O, HTTP REST API, WebSocket, raw TCP
- **Autonomous task scheduling**: area-based inventory planning, layer-by-layer scanning, automatic charging management
- **Three independent sensor subsystems**: RFID reader, machine vision camera, scanning mechanism controller

### Key Specifications

| Parameter | Value |
|-----------|-------|
| **PLC Platform** | CODESYS Control for Linux SL V4.6 |
| **Motion Library** | CODESYS SoftMotion V4.15 (29 libraries) |
| **Fieldbus** | EtherCAT with Distributed Clock synchronization |
| **Drive Protocol** | CiA 402 / DS402 — Cyclic Synchronous Position (CSP) |
| **Interpolation Cycle** | 1ms |
| **EtherCAT Slaves** | 10 devices (2 stepper drives + 7 I/O terminals + 1 bus coupler) |
| **Communication Protocols** | EtherCAT CoE, Modbus TCP, HTTP REST, WebSocket, TCP Socket |
| **HMI** | CODESYS Web Visualization (HTML5) |
| **User-Defined POUs** | 37 program organization units |
| **Compiled Libraries** | 179 dependencies |

---

## System Architecture

```mermaid
graph TB
    subgraph Library Network
        NAV["Navigation PC<br/>192.168.3.100:7000<br/>SLAM · Path Planning · Chassis Control"]
        NR["Node-RED<br/>10.10.3.1:1880"]
        RFID["RFID Reader"]
        VISION["Vision Camera"]
    end

    subgraph CODESYS PLC - Linux SL <br/> 192.168.100.101
        MAIN["MainTask ~10ms<br/>AGV State Machine<br/>HTTP/TCP Client"]
        ETC_TASK["EtherCAT_Task 1ms<br/>SoftMotion Axis Control<br/>PDO Exchange"]
        VISU["VISU_TASK ~50ms<br/>Web HMI HTML5"]
    end

    subgraph EtherCAT Bus - 1ms DC-Sync
        DRV1["XINJE DP3C #1<br/>Vertical Lift Axis"]
        DRV2["XINJE DP3C #2<br/>Secondary Axis"]
        IO["I/O Terminals ×7<br/>+ Bus Coupler"]
    end

    MB["Modbus TCP I/O<br/>E-Stop · Axis Enable · Lights"]

    NAV <-->|"HTTP REST + WebSocket<br/>/api/template/navigating<br/>/api/charging/start·stop<br/>/api/ws"| MAIN
    NR <-->|"HTTP POST<br/>/istore"| MAIN
    RFID <-->|"TCP Socket<br/>DataTransReq/Rec"| MAIN
    VISION <-->|"TCP Socket"| MAIN

    ETC_TASK -->|"CSP 0x607A"| DRV1
    ETC_TASK -->|"CSP 0x607A"| DRV2
    ETC_TASK --> IO

    MAIN --> MB
    MAIN --> ETC_TASK
```

## Mechanical Design

```mermaid
graph TB
    subgraph Scanning Head
        SENSOR["RFID Antenna Array + Camera<br/>Mounted on linear carriage"]
    end

    subgraph Linear Guide Rail
        RAIL["XINJE DP3C #1 — Axis 01<br/>Closed-loop stepper drive<br/>Belt/ballscrew transmission<br/>Travel: LowerLevel → UpperLevel<br/>Resolution: ~250-350mm per shelf layer"]
    end

    subgraph AGV Chassis
        direction LR
        NAV_PC["Navigation PC<br/>SLAM"]
        PLC["CODESYS PLC<br/>Linux SL"]
        MODBUS["Modbus I/O"]
        BATT["Battery Pack"]
        LW["Left Wheel"]
        RW["Right Wheel"]
    end

    SENSOR --- RAIL
    RAIL --- PLC
    NAV_PC --- PLC
    PLC --- MODBUS
    PLC --- BATT
    NAV_PC -.- LW
    NAV_PC -.- RW
```

## Source Code (IEC 61131-3 Structured Text)

Representative ST code illustrating key control patterns. See [`src/README.md`](src/README.md) for details.

| File | Lines | Description |
|------|-------|-------------|
| [`AgvControl_FB.st`](src/agv_control/AgvControl_FB.st) | ~280 | Master AGV state machine — full IDLE→Navigate→Scan→Charge cycle |
| [`AxisControl_FB.st`](src/motion/AxisControl_FB.st) | ~200 | Single-axis motion controller wrapping 10 MC_ function blocks |
| [`NavigationApiClient.st`](src/communication/NavigationApiClient.st) | ~170 | HTTP REST client with JSON body construction |
| [`SensorTcpClient.st`](src/communication/SensorTcpClient.st) | ~170 | TCP socket client for RFID/Vision with reconnection logic |
| [`GVL_Servo.st`](src/global_variables/GVL_Servo.st) | ~80 | Axis configuration — limits, presets, runtime status |
| [`GVL_Main.st`](src/global_variables/GVL_Main.st) | ~70 | Core application variables — waypoints, tasks, diagnostics |
| [`St_PointAxis.st`](src/data_types/St_PointAxis.st) | ~80 | Data types — waypoint struct, state enums, shelf config |

## Documentation

| Document | Description |
|----------|-------------|
| [System Architecture](docs/system-architecture.md) | Full network topology, hardware layout, software stack |
| [Motion Control](docs/motion-control.md) | SoftMotion configuration, DS402 state machine, trajectory planning |
| [EtherCAT Configuration](docs/ethercat-configuration.md) | Bus topology, PDO mapping, XINJE DP3C drive setup |
| [Communication Protocols](docs/communication-protocols.md) | REST API endpoints, WebSocket, TCP, Modbus mapping |
| [State Machine](docs/state-machine.md) | AGV control flow, inventory scanning algorithm |
| [Safety Design](docs/safety-design.md) | E-Stop architecture, fault handling, axis protection |
| [HMI Interface](docs/hmi-interface.md) | Complete HMI variable reference (67 variables) |

## Configuration Files

| File | Description |
|------|-------------|
| [XINJE DP3C ESI](config/xinje-dp3c-esi.xml) | EtherCAT Slave Information file for the stepper drive |
| [XINJE DP3C Device](config/xinje-dp3c-device.xml) | CODESYS device description with PDO/SDO configuration |
| [SoftMotion Profile](config/softmotion-profile.xml) | Library resolution profile (29 motion libraries) |

## Technology Stack

```mermaid
block-beta
    columns 1
    block:APP["APPLICATION LAYER"]
        A1["AGV State Machine"] A2["Inventory Scheduler"] A3["HMI (HTML5)"]
    end
    block:COMM["COMMUNICATION LAYER"]
        B1["HTTP REST Client"] B2["WebSocket"] B3["TCP Client/Server"] B4["JSON"]
    end
    block:MOTION["MOTION CONTROL LAYER"]
        C1["SoftMotion V4.15"] C2["PLCopen MC_ Function Blocks"]
    end
    block:BUS["FIELDBUS LAYER"]
        D1["EtherCAT Master"] D2["DS402 CSP Mode"] D3["Modbus TCP Master"]
    end
    block:HW["HARDWARE LAYER"]
        E1["XINJE DP3C(L) ×2"] E2["I/O Terminals ×7"] E3["Modbus I/O"]
    end

    APP --> COMM --> MOTION --> BUS --> HW
```

## License

This repository contains technical documentation and configuration files for an industrial AGV control system. The CODESYS project source code is proprietary and not included. Hardware-specific configuration files (ESI XML) are provided for reference.

MIT License — Documentation and diagrams only.
