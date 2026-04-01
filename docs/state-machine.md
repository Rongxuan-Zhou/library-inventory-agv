# AGV State Machine & Inventory Scanning Algorithm

## 1. Master State Machine

```
                            ┌──────────┐
                   ┌───────►│  IDLE    │◄──────────────────────────┐
                   │        └────┬─────┘                           │
                   │             │ HMI_Start_PB                    │
                   │             │ (after HMI_Start_Delay)         │
                   │        ┌────▼──────────────┐                  │
                   │        │ NAVIGATE_TO_SHELF  │                 │
                   │        │ api/template/      │                 │
                   │        │   navigating       │                 │
                   │        └────┬───────────────┘                 │
                   │             │                                  │
                   │        ┌────▼──────────────┐                  │
                   │        │ WAIT_NAVIGATION    │                 │
                   │        │ api_navigatting_   │                 │
                   │        │   staus (polling)  │                 │
                   │        └────┬───────────────┘                 │
                   │             │ Navigation complete              │
                   │        ┌────▼──────────────┐                  │
                   │        │ DOCKING            │                 │
                   │        │ Precise alignment  │                 │
                   │        │ to bookshelf       │                 │
                   │        └────┬───────────────┘                 │
                   │             │ Docking confirmed                │
                   │        ┌────▼──────────────┐                  │
                   │        │ START_SCAN         │                 │
                   │        │ AgvRob_Start       │                 │
                   │        │ MC_Home → zero axis│                 │
                   │        └────┬───────────────┘                 │
                   │             │ Homed                            │
                   │        ┌────▼──────────────┐                  │
                   │    ┌──►│ MOVE_TO_LAYER      │                 │
                   │    │   │ MC_MoveAbsolute    │                 │
                   │    │   │ (layer×FloorHeight)│                 │
                   │    │   └────┬───────────────┘                 │
                   │    │        │ In position                     │
                   │    │   ┌────▼──────────────┐                  │
                   │    │   │ SCAN_LAYER         │                 │
                   │    │   │ RFID + Vision      │                 │
                   │    │   │ api_DataTransReq/  │                 │
                   │    │   │   Rec              │                 │
                   │    │   └────┬───────────────┘                 │
                   │    │        │                                  │
                   │    │        ├── More layers? ─── YES ──┘      │
                   │    │        │                                  │
                   │    │        │ NO (all layers done)             │
                   │    │   ┌────▼──────────────┐                  │
                   │    │   │ AREA_DONE          │                 │
                   │    │   │ POST to istore     │                 │
                   │    │   │ Undocking           │                 │
                   │    │   └────┬───────────────┘                 │
                   │    │        │                                  │
                   │    │        ├── More areas? ─── YES ──────────┤
                   │    │        │          (→ NAVIGATE_TO_SHELF)  │
                   │    │        │                                  │
                   │    │        ├── Battery low? ── YES ──┐       │
                   │    │        │                          │       │
                   │    │   ┌────▼──────────────┐   ┌──────▼─────┐│
                   │    │   │ COMPLETE           │   │GO_CHARGING ││
                   │    │   │ Return to home     │   │Navigate to ││
                   │    │   │ aPointHomeName     │   │charge stn  ││
                   │    │   └────┬───────────────┘   │charge/start││
                   │    │        │                    │Wait full   ││
                   │    │        │                    │charge/stop ││
                   │    │        │                    │Undock      ││
                   │    │        │                    └──────┬─────┘│
                   │    │        │                           │      │
                   │    │        │              Resume task ─┘      │
                   │    │        │              (→ NAVIGATE_TO_SHELF)
                   │    │        │                                  │
                   └────┘   ┌────▼──────────────┐                  │
                            │ IDLE               │──────────────────┘
                            └────────────────────┘

        ANY STATE ──── Fault ────►┌───────────┐
                                  │  ERROR     │
                                  │ MC_Stop    │
                                  │ All axes   │
                                  └─────┬──────┘
                                        │ HMI_Rest_PB
                                        │ MC_Reset
                                        ▼
                                  ┌───────────┐
                                  │ HOMING     │──► IDLE
                                  └───────────┘
```

## 2. Inventory Scanning Algorithm

### 2.1 Input Parameters (from HMI)

| Parameter | Variable | Example | Description |
|-----------|----------|---------|-------------|
| Area number | `HMI_AreaNum` | 3 | Library zone to inventory |
| Shelf type | `HMI_BookShelTypeNum2` | 2 | Shelf model (different dimensions) |
| Total floors | `HMI_TotalFloors` | 6 | Number of layers in shelf |
| Floor height | `HMI_FloorHeight` | 300.0 | Distance between layers (mm) |
| Upper level | `HMI_UpperLevel` | 6 | Top scan boundary |
| Lower level | `HMI_LowerLevel` | 1 | Bottom scan boundary |
| Upper start layer | `HMI_UpperStartLayerNumber` | 6 | First layer when scanning top-down |
| Lower start layer | `HMI_LowerStartLayerNumber` | 1 | First layer when scanning bottom-up |

### 2.2 Scanning Pseudocode

```
FUNCTION_BLOCK InventoryScan:

VAR
    nCurrentLayer    : INT;
    rTargetPosition  : REAL;
    nBooksThisLayer  : INT;
    eState           : E_ScanState;
END_VAR

CASE eState OF

    SCAN_INIT:
        nCurrentLayer := HMI_LowerStartLayerNumber;
        HMI_Physicaliinventory1 := 0;
        eState := SCAN_MOVE;

    SCAN_MOVE:
        rTargetPosition := INT_TO_REAL(nCurrentLayer) * HMI_FloorHeight;
        
        MC_MoveAbsolute_ETC(
            Axis         := stAxis01,
            Execute      := TRUE,
            Position     := rTargetPosition,
            Velocity     := fMaxVelocity,
            Acceleration := fMaxAcceleration,
            Deceleration := fMaxDeceleration,
            Jerk         := fMaxJerk
        );
        
        IF fbMoveAbs.Done THEN
            eState := SCAN_READ;
        ELSIF fbMoveAbs.Error THEN
            eState := SCAN_ERROR;
        END_IF

    SCAN_READ:
        // Trigger RFID reader
        api_DataTransReq(Execute := TRUE);
        
        IF api_DataTransRec.Done THEN
            nBooksThisLayer := ParseRFIDResponse();
            HMI_Physicaliinventory1 := HMI_Physicaliinventory1 + nBooksThisLayer;
            
            nCurrentLayer := nCurrentLayer + 1;
            
            IF nCurrentLayer <= HMI_UpperStartLayerNumber THEN
                eState := SCAN_MOVE;    // Next layer
            ELSE
                eState := SCAN_COMPLETE;
            END_IF
        END_IF

    SCAN_COMPLETE:
        HMI_AreaInveDone := TRUE;
        HMI_InveAreaNumCml := HMI_InveAreaNumCml + 1;
        // Upload results to Node-RED
        HttpPost(url := 'http://10.10.3.1:1880/istore', data := inventoryData);

    SCAN_ERROR:
        MC_Stop_ETC(Axis := stAxis01, Execute := TRUE);
        // Report error to HMI

END_CASE
```

### 2.3 Scan Timing Estimate

| Phase | Duration | Notes |
|-------|----------|-------|
| Move to layer (300mm, 300mm/s) | ~2s | Including S-curve accel/decel |
| Settle + trigger | ~0.3s | Position settling + command latency |
| RFID scan | ~1-3s | Depends on tag count per shelf |
| Vision capture | ~0.5-1s | If vision is triggered per layer |
| **Per layer total** | **~4-6s** | |
| **6-layer shelf total** | **~25-35s** | |
| Navigation between shelves | ~15-30s | Depends on library layout |

## 3. Task Scheduling

### 3.1 Area-Based Inventory

The library is divided into areas, each containing multiple bookshelves:

```
Library Floor Plan:
  ┌─────────────────────────────────────────┐
  │  Area 1      │  Area 2      │  Area 3   │
  │  ═══ ═══ ═══ │  ═══ ═══ ═══ │  ═══ ═══  │  ═══ = Bookshelf
  │  ═══ ═══ ═══ │  ═══ ═══ ═══ │  ═══ ═══  │
  │              │              │           │
  │  ═══ ═══ ═══ │  ═══ ═══ ═══ │  ═══ ═══  │
  │              │              │           │
  │  [Charging]  │              │  [Home]   │
  └─────────────────────────────────────────┘

Workflow:
  1. Operator selects areas to inventory (HMI_AreaNum)
  2. System generates waypoint list (aPointsName[])
  3. AGV navigates to first shelf → scan → next shelf → ...
  4. Area complete → move to next area
  5. All areas done → return to home
```

### 3.2 Timed Automatic Inventory

```
HMI_Timer_Enable := TRUE;
HMI_Timer_H3 := 2;    // Hour: 02:00 AM
HMI_Timer_M3 := 0;    // Minute: 00

→ AGV automatically starts inventory at 2:00 AM daily
→ Scans configured areas
→ Returns to charging station when done
```

### 3.3 Output Data

| Variable | Type | Description |
|----------|------|-------------|
| `HMI_Physicaliinventory1` | INT/DINT | Running count of books scanned |
| `HMI_PhysicaliinventoryLast1` | INT/DINT | Previous session scan count |
| `HMI_AreaInveDone` | BOOL | Current area scan complete flag |
| `HMI_AreaCurrTaskNum1` | INT | Current task sequence number |
| `HMI_InveAreaNum` | INT | Areas to inventory |
| `HMI_InveAreaNumCml` | INT | Cumulative areas completed |
