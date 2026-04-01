// =============================================================================
// GVL_Main — Core Application Variables
// =============================================================================

{attribute 'qualified_only'}
VAR_GLOBAL
    // =========================================================================
    // AGV Master Control
    // =========================================================================
    fbAgvControl    : AgvControl_FB;        // Master state machine instance
    eAgvState       : E_AgvState;           // Current AGV state (mirrored for HMI)

    // =========================================================================
    // Navigation Waypoints
    // =========================================================================
    aPointsName     : ARRAY[0..99] OF STRING(80);   // Navigation point names
    aPointsName01   : ARRAY[0..99] OF STRING(80);   // Alternate point list
    aPointChargingName : STRING(80) := 'Charging_01'; // Charging station point
    aPointHomeName     : STRING(80) := 'Home_01';     // Home/standby point
    spointsName     : STRING(80);           // Currently active point name
    iPointCount     : INT;                  // Total waypoints in current task
    nPointPosition  : INT;                  // Current waypoint index

    // =========================================================================
    // Task Management
    // =========================================================================
    sTask_Number    : STRING(40);           // Current task ID
    sTask_Number1   : STRING(40);           // Previous task ID
    nAreaCount      : INT;                  // Number of areas to scan
    nCurrentArea    : INT;                  // Current area index

    // =========================================================================
    // Shelf Configuration (loaded from HMI_BookShelfSeting)
    // =========================================================================
    stCurrentShelf  : ST_ShelfConfig;       // Active shelf parameters

    // =========================================================================
    // Sensor Clients
    // =========================================================================
    fbRfidClient    : SensorTcpClient;      // RFID reader TCP connection
    fbVisionClient  : SensorTcpClient;      // Vision camera TCP connection

    // =========================================================================
    // Communication Status
    // =========================================================================
    bNavSystemOnline    : BOOL;             // Navigation API reachable
    bNodeRedOnline      : BOOL;             // Node-RED data store reachable
    bRfidConnected      : BOOL;             // RFID reader TCP connected
    bVisionConnected    : BOOL;             // Vision camera TCP connected
    bRobConnected       : BOOL;             // Scanning mechanism connected

    // =========================================================================
    // Modbus I/O Mirrors
    // =========================================================================
    bEStopActive    : BOOL;                 // Emergency stop pressed
    bAx01_PowerOn   : BOOL;                 // Axis 01 enable output
    bAx02_PowerOn   : BOOL;                 // Axis 02 enable output
    bLight01_On     : BOOL;                 // Warning light 1
    bLight02_On     : BOOL;                 // Warning light 2

    // =========================================================================
    // Diagnostics
    // =========================================================================
    udiMainTaskCycCount : UDINT;            // Cycle counter (overflow = ~49 days at 10ms)
    tSystemUptime       : TIME;             // System uptime
END_VAR
