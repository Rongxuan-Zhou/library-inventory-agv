# Communication Protocols

## 1. HTTP REST API — Navigation System

The PLC communicates with an external navigation system at `192.168.3.100:7000` using HTTP REST APIs for task management, navigation control, and charging operations.

### 1.1 JSON Construction

The PLC builds JSON request bodies using the CODESYS `JSON Utilities SL` library:

```
Components:
  - fb_JBuilder         → JSON object builder
  - JSONByteArrayWriter → Serializes JSON to byte buffer
  - wsJsonData          → WSTRING(1000) output buffer (2000 bytes)
  - pJsonData           → Pointer to JSON.JSONData managed by factory
  - Content-Type        → application/json
```

### 1.2 Complete API Endpoint Reference

#### Navigation Control

| Endpoint | Method | Purpose | Request Body (Inferred) |
|----------|--------|---------|------------------------|
| `POST /api/template/navigating` | POST | Submit navigation task template with waypoint list | `{"task_number": "<id>", "points": ["Shelf_A01", "Shelf_A02", ...]}` |
| `POST /api/template/confirm` | POST | Confirm and start the submitted navigation template | `{"task_number": "<id>"}` |
| `POST /api/navigating/stop` | POST | Abort current navigation | `{}` |

#### Charging Station

| Endpoint | Method | Purpose | Request Body (Inferred) |
|----------|--------|---------|------------------------|
| `POST /api/navigating/charging_station/docking` | POST | Navigate to charging station and dock | `{"point": "<charging_point_name>", "x": 1000.0, "y": 500.0, "a": 90.0}` |
| `POST /api/navigating/charging_station/undocking` | POST | Undock from charging station | `{}` |
| `POST /api/charging/start` | POST | Begin charging process | `{}` |
| `POST /api/charging/stop` | POST | End charging process | `{}` |

#### Docking Control

| Endpoint | Method | Purpose | Request Body (Inferred) |
|----------|--------|---------|------------------------|
| `POST /api/docking/cancel` | POST | Cancel ongoing docking operation | `{}` |

#### Real-Time Status

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `ws://192.168.3.100:7000/api/ws` | WebSocket | Bidirectional real-time status updates |

### 1.3 Navigation Waypoint Data Model

```
TYPE St_PointAxis :
STRUCT
    sName    : STRING;    // Waypoint name (e.g., "Shelf_A01", "Charging_01")
    rX       : REAL;      // X coordinate (mm)
    rY       : REAL;      // Y coordinate (mm)
    rA       : REAL;      // Orientation angle (degrees)
    rAxisPos : REAL;      // Associated axis position (mm) — optional
END_STRUCT
END_TYPE
```

**Global waypoint variables:**

| Variable | Type | Purpose |
|----------|------|---------|
| `aPointsName` | ARRAY OF STRING | Navigation waypoint name list |
| `aPointsName01` | ARRAY OF STRING | Alternate waypoint list |
| `aPointChargingName` | STRING | Charging station waypoint name |
| `aPointHomeName` | STRING | Home/standby position name |
| `iPointCount` | INT | Total waypoint count |
| `nPointPosition` | INT | Current waypoint index |
| `sTask_Number` | STRING | Current task identifier |

### 1.4 Message Templates

| Variable | Purpose |
|----------|---------|
| `start_Messag00` | Navigation start message template #0 |
| `start_Messag01` | Navigation start message template #1 |
| `gc_sJsonTask` | JSON task template constant string |

## 2. WebSocket — Real-Time Status

```
Connection: ws://192.168.3.100:7000/api/ws

Implementation:
  - IWebSocketClient interface (CODESYS Web Client SL)
  - WSSendBuffer for outgoing messages
  - m_bStatusRequested flag for status polling

Features:
  - OAuth2 support (gc_wsGrantTypeClient, gc_wsClientId, gc_wsClientSecret)
  - Response type handling (gc_wsResponseTypeCode, gc_wsResponseTypeToken)
  - JSON message framing (gc_wsObjStart, gc_wsArrayStart, etc.)
```

## 3. TCP Socket — Sensor Communication

### 3.1 RFID Reader Interface

```
Protocol: Raw TCP socket
Connection Status: HMI_RFID_ConnectionActive (BOOL)

Data Flow:
  1. PLC sends scan trigger → api_DataTransReq
  2. RFID reader scans shelf → reads all RFID tags in range
  3. Reader returns tag data → api_DataTransRec
  4. PLC parses results → updates inventory count
  
  TCP_ReadCk → Read with checksum verification
```

### 3.2 Machine Vision Interface

```
Protocol: Raw TCP socket
Connection Status: HMI_Vision_ConnectionActive (BOOL)

Data Flow:
  1. PLC sends capture trigger → via TCP_Client
  2. Camera captures book spine images
  3. Camera returns recognition results → via TCP_Read
  4. PLC correlates with RFID data
```

### 3.3 Scanning Mechanism (AgvRob) Interface

"AgvRob" (AGV Robot) refers to the vertical scanning mechanism controller — the subsystem that manages the linear guide rail carriage carrying the RFID antenna and vision camera. This may be an independent embedded controller or an I/O module that handles low-level carriage motion coordination.

```
Protocol: Raw TCP socket
Connection Status: HMI_AGVROB_ConnectionActive (BOOL)

Control:
  AgvRob_Start  → Start scanning mechanism
  AgvRob_Sttus  → Read mechanism status (as-coded spelling)

Note: "Sttus" is the original variable name in the CODESYS project.
```

## 4. Node-RED Data Storage

```
Endpoint: POST http://10.10.3.1:1880/istore
Content-Type: application/x-www-form-urlencoded

Purpose: Persist completed inventory scan results
Trigger: After each area scan completion (HMI_AreaInveDone = TRUE)

Data includes:
  - Area number
  - Books scanned count (HMI_Physicaliinventory1)
  - Timestamp
  - Task identifier
```

## 5. Modbus TCP — Remote I/O

```
Protocol: Modbus TCP (Master mode)
Library: IoDrvModbusTCP V4.3.0.0

Mapped Signals:
  ┌────────────────────────┬──────────┬──────────┐
  │ Variable               │ Direction│ Purpose  │
  ├────────────────────────┼──────────┼──────────┤
  │ modbus_E_Stop          │ Input    │ E-Stop   │
  │ modbus_Axi01_PowerOn   │ Output   │ Axis 1   │
  │ modbus_Axi02_PowerOn   │ Output   │ Axis 2   │
  │ modbus_Light01_PowerOn │ Output   │ Light 1  │
  │ modbus_Light02_PowerOn │ Output   │ Light 2  │
  └────────────────────────┴──────────┴──────────┘
```
