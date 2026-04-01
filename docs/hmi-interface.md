# HMI Interface — Complete Variable Reference

The HMI is implemented using CODESYS Web Visualization (HTML5), accessible via any web browser on the local network. The interface exposes 67 operator-facing variables organized into functional groups.

> **Note on variable naming**: Several variable names contain spelling variations from the original development (e.g., `Homeing` for "Homing", `Rest` for "Reset", `bBttery` for "Battery", `Sttus` for "Status"). These are the **actual as-coded identifiers** in the CODESYS project. Descriptions in this document use standard English spelling for clarity.

## 1. Axis Control Panel

### Axis 01 (Vertical Lift)

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_Ax01_AbsP01_PB` | BOOL | Button | Move to preset position P01 (e.g., shelf bottom) |
| `HMI_Ax01_AbsP02_PB` | BOOL | Button | Move to preset position P02 (e.g., shelf top) |
| `HMI_Ax01_Fault` | BOOL | Indicator | Axis fault active |
| `HMI_Ax01_fJogVel` | REAL | Input | Manual jog velocity setpoint (mm/s) |
| `HMI_Ax01_Homeing_LP` | BOOL | Indicator | Homing complete lamp |
| `HMI_Ax01_Homeing_PB` | BOOL | Button | Trigger homing sequence |
| `HMI_Ax01_JogN_PB` | BOOL | Button | Jog negative direction (down) |
| `HMI_Ax01_JogP_PB` | BOOL | Button | Jog positive direction (up) |

### Axis 02

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_Ax02_AbsP01_PB` | BOOL | Button | Move to preset position P01 |
| `HMI_Ax02_AbsP02_PB` | BOOL | Button | Move to preset position P02 |
| `HMI_Ax02_Fault` | BOOL | Indicator | Axis fault active |
| `HMI_Ax02_fJogVel` | REAL | Input | Manual jog velocity setpoint (mm/s) |
| `HMI_Ax02_Homeing_LP` | BOOL | Indicator | Homing complete lamp |
| `HMI_Ax02_Homeing_PB` | BOOL | Button | Trigger homing sequence |
| `HMI_Ax02_JogN_PB` | BOOL | Button | Jog negative direction |
| `HMI_Ax02_JogP_PB` | BOOL | Button | Jog positive direction |

## 2. Inventory Task Configuration

### Area Selection

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_AreaNum` | INT | Input | Target area number for inventory |
| `HMI_AreaSelc` | INT | Input | Area selection index |
| `HMI_AreaSeclShow` | — | Display | Area selection display |
| `HMI_AreaPointsBase` | ARRAY | Config | Base waypoint data for selected area |
| `HMI_AreaCurrTaskNum1` | INT | Display | Current task sequence number |

### Bookshelf Configuration

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_BookShelfSeting` | STRUCT | Config | Bookshelf parameter set |
| `HMI_BookShelTypeNum2` | INT | Input | Bookshelf type number (size category) |
| `HMI_FloorHeight` | REAL | Input | Layer-to-layer height (mm) |
| `HMI_TotalFloors` | INT | Input | Total number of shelf layers |
| `HMI_UpperLevel` | INT | Input | Upper scanning boundary (layer number) |
| `HMI_LowerLevel` | INT | Input | Lower scanning boundary (layer number) |
| `HMI_UpperStartLayerNumber` | INT | Input | Starting layer for top-down scan |
| `HMI_LowerStartLayerNumber` | INT | Input | Starting layer for bottom-up scan |

### Inventory Progress

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_InveAreaNum` | INT | Display | Inventory area number |
| `HMI_InveAreaNumCml` | INT | Display | Cumulative areas inventoried |
| `HMI_AreaInveDone` | BOOL | Indicator | Current area scan complete |
| `HMI_Physicaliinventory1` | INT/DINT | Display | Books scanned this session |
| `HMI_PhysicaliinventoryLast1` | INT/DINT | Display | Books scanned last session |

## 3. AGV Control

### Start / Stop / Reset

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_Start_PB` | BOOL | Button | Start inventory task |
| `HMI_Start_Ons` | BOOL | Internal | Start one-shot trigger |
| `HMI_Start_Delay` | TIME | Config | Delay before task begins |
| `HMI_SingerStart` | BOOL | Button | Single-cycle start (one area only) |
| `HMI_Rest_PB` | BOOL | Button | Reset from error state |
| `HMI_init_PB` | BOOL | Button | System initialization |
| `HMI_initDelay` | TIME | Config | Initialization delay |
| `HMI_Task_Rest_PB` | BOOL | Button | Reset current task |
| `HMI_Task_CML_Lamp` | BOOL | Indicator | Task complete lamp |

### Navigation Control

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_DockingCancel` | BOOL | Button | Cancel active docking operation |
| `HMI_NavigatingCancel` | BOOL | Button | Cancel active navigation |

### Status Lights

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_EStopOK_LP` | BOOL | Indicator | E-Stop released (safe to operate) |
| `HMI_Light01_PB` | BOOL | Button | Toggle warning light #1 |
| `HMI_Light02_PB` | BOOL | Button | Toggle warning light #2 |

## 4. Docking & Charging

### Docking Coordinates

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_AGVDocking_x` | REAL | Input | Docking X coordinate (mm) |
| `HMI_AGVDocking_y` | REAL | Input | Docking Y coordinate (mm) |
| `HMI_AGVDocking_a` | REAL | Input | Docking orientation angle (deg) |
| `HMI_AGVDockingStart` | BOOL | Button | Start docking sequence |
| `HMI_AGVUnDocking_x` | REAL | Input | Undocking X coordinate |
| `HMI_AGVUnDocking_y` | REAL | Input | Undocking Y coordinate |
| `HMI_AGVUnDocking_a` | REAL | Input | Undocking orientation angle |
| `HMI_AGVUnDockingStart` | BOOL | Button | Start undocking sequence |

### Charging

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_AGVChargingStart` | BOOL | Button | Start charging |
| `HMI_AGVChargingStartMPb` | BOOL | Button | Charging start (momentary) |
| `HMI_AGVChargingStop` | BOOL | Button | Stop charging |
| `HMI_AGVChargingStopMPb` | BOOL | Button | Charging stop (momentary) |
| `HMI_AGVbBttery` | REAL/INT | Display | Battery level |

## 5. Connection Status & Timer

### Sensor Connection Status

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_RFID_ConnectionActive` | BOOL | Indicator | RFID reader TCP connection alive |
| `HMI_Vision_ConnectionActive` | BOOL | Indicator | Vision camera TCP connection alive |
| `HMI_AGVROB_ConnectionActive` | BOOL | Indicator | Scanning mechanism connection alive |

### Scheduled Inventory Timer

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_Timer_Enable` | BOOL | Toggle | Enable timed automatic inventory |
| `HMI_Timer_H3` | INT | Input | Scheduled hour (0-23) |
| `HMI_Timer_M3` | INT | Input | Scheduled minute (0-59) |

### Diagnostics

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `HMI_MainTaskCycCount` | UDINT | Display | Main task cycle counter (uptime indicator) |
