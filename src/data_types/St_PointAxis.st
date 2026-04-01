// =============================================================================
// St_PointAxis — Navigation Waypoint Data Structure
// =============================================================================
// Represents a single navigation waypoint with associated axis position data.
// Used by AgvPointsInfor to manage the ordered list of shelf locations
// that the AGV visits during an inventory scan cycle.
// =============================================================================

TYPE St_PointAxis :
STRUCT
    sName       : STRING(80);   // Waypoint identifier (e.g., 'Shelf_A01', 'Charging_01')
    rX          : REAL;         // X coordinate in map frame (mm)
    rY          : REAL;         // Y coordinate in map frame (mm)
    rA          : REAL;         // Orientation angle at waypoint (degrees, 0-360)
    rAxisPos    : REAL;         // Scan start position for vertical axis (mm), 0 if N/A
END_STRUCT
END_TYPE

// =============================================================================
// St_PointAxis_IF — Extended Waypoint with Interface Flags
// =============================================================================

TYPE St_PointAxis_IF :
STRUCT
    stPoint     : St_PointAxis; // Base waypoint data
    bVisited    : BOOL;         // TRUE after this shelf has been scanned
    bSkipped    : BOOL;         // TRUE if operator chose to skip this shelf
    nLayersDone : INT;          // Number of layers completed at this shelf
END_STRUCT
END_TYPE

// =============================================================================
// E_AgvState — AGV Master State Machine Enumeration
// =============================================================================

TYPE E_AgvState :
(
    AGV_IDLE            := 0,
    AGV_NAVIGATE        := 10,
    AGV_WAIT_NAV        := 20,
    AGV_DOCKING         := 30,
    AGV_START_SCAN      := 40,
    AGV_MOVE_TO_LAYER   := 50,
    AGV_SCAN_LAYER      := 60,
    AGV_AREA_DONE       := 70,
    AGV_GO_CHARGING     := 80,
    AGV_CHARGING        := 90,
    AGV_UNDOCKING       := 100,
    AGV_COMPLETE        := 110,
    AGV_ERROR           := 200,
    AGV_HOMING          := 210
);
END_TYPE

// =============================================================================
// E_ScanState — Layer Scanning Sub-State
// =============================================================================

TYPE E_ScanState :
(
    SCAN_IDLE       := 0,
    SCAN_INIT       := 1,
    SCAN_MOVE       := 2,
    SCAN_SETTLING   := 3,
    SCAN_TRIGGER    := 4,
    SCAN_WAIT_DATA  := 5,
    SCAN_COMPLETE   := 6,
    SCAN_ERROR      := 99
);
END_TYPE

// =============================================================================
// ST_ShelfConfig — Bookshelf Physical Configuration
// =============================================================================

TYPE ST_ShelfConfig :
STRUCT
    nShelfType      : INT;      // Shelf model number
    nTotalFloors    : INT;      // Total layers in this shelf type
    rFloorHeight    : REAL;     // Distance between layers (mm)
    rFirstFloorOffset : REAL;   // Height of bottom layer from ground (mm)
    rShelfWidth     : REAL;     // Width of one shelf unit (mm)
    rScanDepth      : REAL;     // RFID effective read depth (mm)
END_STRUCT
END_TYPE
