// =============================================================================
// AgvControl_FB — Master AGV State Machine
// =============================================================================
// Top-level controller that orchestrates the complete inventory workflow:
//   IDLE → Navigate → Dock → Scan (layer-by-layer) → Undock → Next shelf
//
// Coordinates between:
//   - Navigation system (HTTP REST API at 192.168.3.100:7000)
//   - Motion control (SoftMotion axis for vertical lift)
//   - Sensor systems (RFID + Vision via TCP)
//   - Charging management (automatic when battery low)
//
// Called cyclically from MainTask (~10ms cycle).
// =============================================================================

FUNCTION_BLOCK AgvControl_FB
VAR_INPUT
    bStart          : BOOL;     // HMI_Start_PB — start inventory cycle
    bSingleStart    : BOOL;     // HMI_SingerStart — single area only
    bReset          : BOOL;     // HMI_Rest_PB — reset from error
    bDockingCancel  : BOOL;     // HMI_DockingCancel
    bNavCancel      : BOOL;     // HMI_NavigatingCancel
    bEStopOK        : BOOL;     // HMI_EStopOK_LP — E-Stop released
    rBatteryLevel   : REAL;     // HMI_AGVbBttery — battery percentage

    // Shelf configuration (from HMI)
    stShelfConfig   : ST_ShelfConfig;
    nAreaNum        : INT;      // HMI_AreaNum
    nLowerStart     : INT;      // HMI_LowerStartLayerNumber
    nUpperStart     : INT;      // HMI_UpperStartLayerNumber
END_VAR

VAR_OUTPUT
    eState          : E_AgvState;   // Current state (for HMI display)
    bBusy           : BOOL;         // Task in progress
    bDone           : BOOL;         // All areas completed
    bError          : BOOL;         // Error state active
    nAreasCompleted : INT;          // HMI_InveAreaNumCml
    nBooksScanned   : DINT;        // HMI_Physicaliinventory1
END_VAR

VAR
    // Sub-function block instances
    fbAxisCtrl      : AxisControl_FB;
    fbNavStart      : api_navigatting_start;
    fbNavStatus     : api_navigatting_staus;
    fbNavPost       : api_navigatting_Post;
    fbDocking       : api_navigatting_docking;
    fbUndocking     : api_navigatting_Undocking;
    fbChargingCtrl  : AgvControlCharging_FB;
    fbHomeCtrl      : AgvControlHome_FB;
    fbDataReq       : api_DataTransReq;
    fbDataRec       : api_DataTransRec;

    // State machine internals
    nCurrentPoint   : INT;          // Index into aPointsName[]
    nCurrentLayer   : INT;          // Current shelf layer being scanned
    rTargetPosition : LREAL;        // Computed axis target (mm)

    // Waypoint management
    aPointsName     : ARRAY[0..99] OF STRING(80);
    iPointCount     : INT;
    sCurrentPoint   : STRING(80);

    // Timing
    tStartDelay     : TON;          // Startup delay timer
    tNavTimeout     : TON;          // Navigation timeout watchdog
    tScanTimeout    : TON;          // Scan response timeout
    tSettleTime     : TON;          // Position settling delay

    // Edge triggers
    rtStart         : R_TRIG;
    rtReset         : R_TRIG;

    // Constants
    C_NAV_TIMEOUT   : TIME := T#60S;     // Navigation must complete within 60s
    C_SCAN_TIMEOUT  : TIME := T#10S;     // RFID scan must respond within 10s
    C_SETTLE_TIME   : TIME := T#300MS;   // Wait 300ms for axis vibration to settle
    C_BATTERY_LOW   : REAL := 20.0;      // Charge threshold (%)
END_VAR

// =========================================================================
// Edge detection
// =========================================================================
rtStart(CLK := bStart);
rtReset(CLK := bReset);

// =========================================================================
// Master State Machine
// =========================================================================
CASE eState OF

// -------------------------------------------------------------------------
// IDLE — Waiting for operator command
// -------------------------------------------------------------------------
AGV_IDLE:
    bBusy := FALSE;
    bDone := FALSE;
    bError := FALSE;

    IF rtStart.Q AND bEStopOK THEN
        // Initialize task
        nCurrentPoint := 0;
        nAreasCompleted := 0;
        nBooksScanned := 0;

        // Load waypoint list for selected area
        // (populated from GVL_Main based on HMI_AreaNum)
        sCurrentPoint := aPointsName[nCurrentPoint];

        tStartDelay(IN := TRUE, PT := T#2S);  // 2s startup delay
        IF tStartDelay.Q THEN
            tStartDelay(IN := FALSE);
            eState := AGV_NAVIGATE;
            bBusy := TRUE;
        END_IF
    END_IF

// -------------------------------------------------------------------------
// NAVIGATE — Send navigation command to external system
// -------------------------------------------------------------------------
AGV_NAVIGATE:
    fbNavStart(
        Execute     := TRUE,
        sPointName  := sCurrentPoint,
        sTaskNumber := CONCAT('TASK_', INT_TO_STRING(nAreasCompleted))
    );

    IF fbNavStart.Done THEN
        fbNavStart(Execute := FALSE);
        tNavTimeout(IN := TRUE, PT := C_NAV_TIMEOUT);
        eState := AGV_WAIT_NAV;
    ELSIF fbNavStart.Error THEN
        eState := AGV_ERROR;
    END_IF

// -------------------------------------------------------------------------
// WAIT_NAV — Poll navigation status until arrival
// -------------------------------------------------------------------------
AGV_WAIT_NAV:
    fbNavStatus(Execute := TRUE);

    IF fbNavStatus.bArrived THEN
        fbNavStatus(Execute := FALSE);
        tNavTimeout(IN := FALSE);
        eState := AGV_DOCKING;

    ELSIF tNavTimeout.Q THEN
        // Navigation timeout — stop and report error
        tNavTimeout(IN := FALSE);
        eState := AGV_ERROR;

    ELSIF bNavCancel THEN
        // Operator cancelled navigation
        fbNavPost(
            Execute := TRUE,
            sUrl    := '/api/navigating/stop'
        );
        eState := AGV_IDLE;
    END_IF

// -------------------------------------------------------------------------
// DOCKING — Precise alignment to bookshelf
// -------------------------------------------------------------------------
AGV_DOCKING:
    fbDocking(Execute := TRUE);

    IF fbDocking.Done THEN
        fbDocking(Execute := FALSE);
        eState := AGV_START_SCAN;

    ELSIF bDockingCancel THEN
        fbDocking(Execute := FALSE);
        fbNavPost(
            Execute := TRUE,
            sUrl    := '/api/docking/cancel'
        );
        eState := AGV_IDLE;

    ELSIF fbDocking.Error THEN
        eState := AGV_ERROR;
    END_IF

// -------------------------------------------------------------------------
// START_SCAN — Initialize scanning mechanism and home axis
// -------------------------------------------------------------------------
AGV_START_SCAN:
    // Enable vertical axis
    fbAxisCtrl.bEnable := TRUE;
    fbAxisCtrl.rAcceleration := 500.0;   // mm/s²
    fbAxisCtrl.rDeceleration := 500.0;
    fbAxisCtrl.rJerk         := 2000.0;  // S-curve jerk

    IF fbAxisCtrl.bEnabled AND NOT fbAxisCtrl.bHomed THEN
        // Start homing sequence
        fbAxisCtrl.bHome := TRUE;
    END_IF

    IF fbAxisCtrl.bHomed THEN
        fbAxisCtrl.bHome := FALSE;
        nCurrentLayer := nLowerStart;
        eState := AGV_MOVE_TO_LAYER;
    END_IF

// -------------------------------------------------------------------------
// MOVE_TO_LAYER — Position scanning head at target shelf layer
// -------------------------------------------------------------------------
AGV_MOVE_TO_LAYER:
    // Compute target position:
    //   Layer 1 = FirstFloorOffset + 0 × FloorHeight
    //   Layer 2 = FirstFloorOffset + 1 × FloorHeight
    //   ...
    rTargetPosition := stShelfConfig.rFirstFloorOffset
                     + INT_TO_LREAL(nCurrentLayer - 1) * REAL_TO_LREAL(stShelfConfig.rFloorHeight);

    fbAxisCtrl.rPosition := rTargetPosition;
    fbAxisCtrl.rVelocity := 300.0;       // mm/s — moderate speed for scanning
    fbAxisCtrl.bMoveAbs  := TRUE;

    IF fbAxisCtrl.bInPosition THEN
        fbAxisCtrl.bMoveAbs := FALSE;
        // Wait for mechanical settling before triggering sensors
        tSettleTime(IN := TRUE, PT := C_SETTLE_TIME);
        IF tSettleTime.Q THEN
            tSettleTime(IN := FALSE);
            eState := AGV_SCAN_LAYER;
        END_IF
    ELSIF fbAxisCtrl.bError THEN
        eState := AGV_ERROR;
    END_IF

// -------------------------------------------------------------------------
// SCAN_LAYER — Trigger RFID + Vision and collect data
// -------------------------------------------------------------------------
AGV_SCAN_LAYER:
    // Step 1: Request RFID scan
    fbDataReq(Execute := TRUE);
    tScanTimeout(IN := TRUE, PT := C_SCAN_TIMEOUT);

    // Step 2: Wait for response
    IF fbDataRec.Done THEN
        fbDataReq(Execute := FALSE);
        tScanTimeout(IN := FALSE);

        // Accumulate scanned book count
        nBooksScanned := nBooksScanned + fbDataRec.nItemCount;

        // Advance to next layer
        nCurrentLayer := nCurrentLayer + 1;

        IF nCurrentLayer <= nUpperStart THEN
            eState := AGV_MOVE_TO_LAYER;    // Next layer
        ELSE
            eState := AGV_AREA_DONE;        // All layers done
        END_IF

    ELSIF tScanTimeout.Q THEN
        // RFID timeout — skip this layer, log warning, continue
        tScanTimeout(IN := FALSE);
        fbDataReq(Execute := FALSE);
        nCurrentLayer := nCurrentLayer + 1;
        IF nCurrentLayer <= nUpperStart THEN
            eState := AGV_MOVE_TO_LAYER;
        ELSE
            eState := AGV_AREA_DONE;
        END_IF
    END_IF

// -------------------------------------------------------------------------
// AREA_DONE — Complete current area, upload results, decide next action
// -------------------------------------------------------------------------
AGV_AREA_DONE:
    nAreasCompleted := nAreasCompleted + 1;

    // Upload inventory results to Node-RED
    fbNavPost(
        Execute := TRUE,
        sUrl    := 'http://10.10.3.1:1880/istore'
        // Body: area number, book count, timestamp
    );

    // Undock from shelf
    fbUndocking(Execute := TRUE);

    IF fbUndocking.Done THEN
        fbUndocking(Execute := FALSE);
        fbNavPost(Execute := FALSE);

        // Decision: next area, charge, or complete?
        IF rBatteryLevel < C_BATTERY_LOW THEN
            eState := AGV_GO_CHARGING;

        ELSIF bSingleStart THEN
            // Single-area mode: done after one area
            eState := AGV_COMPLETE;

        ELSIF nCurrentPoint + 1 < iPointCount THEN
            // More shelves to scan
            nCurrentPoint := nCurrentPoint + 1;
            sCurrentPoint := aPointsName[nCurrentPoint];
            eState := AGV_NAVIGATE;

        ELSE
            // All areas complete
            eState := AGV_COMPLETE;
        END_IF
    END_IF

// -------------------------------------------------------------------------
// GO_CHARGING — Navigate to charging station
// -------------------------------------------------------------------------
AGV_GO_CHARGING:
    fbChargingCtrl(
        bStart          := TRUE,
        sChargingPoint  := aPointChargingName
    );

    IF fbChargingCtrl.bCharged THEN
        fbChargingCtrl(bStart := FALSE);
        // Resume scanning from where we left off
        eState := AGV_NAVIGATE;
    ELSIF fbChargingCtrl.bError THEN
        eState := AGV_ERROR;
    END_IF

// -------------------------------------------------------------------------
// COMPLETE — All tasks done, return to home
// -------------------------------------------------------------------------
AGV_COMPLETE:
    // Disable scanning axis
    fbAxisCtrl.bEnable := FALSE;

    // Navigate to home position
    fbNavStart(
        Execute     := TRUE,
        sPointName  := aPointHomeName
    );

    IF fbNavStart.Done THEN
        fbNavStart(Execute := FALSE);
        bDone := TRUE;
        bBusy := FALSE;
        eState := AGV_IDLE;
    END_IF

// -------------------------------------------------------------------------
// ERROR — Fault handling
// -------------------------------------------------------------------------
AGV_ERROR:
    bError := TRUE;

    // Stop all motion immediately
    fbAxisCtrl.bStop := TRUE;

    IF rtReset.Q AND bEStopOK THEN
        fbAxisCtrl.bStop := FALSE;
        fbAxisCtrl.bReset := TRUE;
        bError := FALSE;
        eState := AGV_HOMING;
    END_IF

// -------------------------------------------------------------------------
// HOMING — Recovery: re-home axis after fault
// -------------------------------------------------------------------------
AGV_HOMING:
    fbAxisCtrl.bReset := FALSE;
    fbAxisCtrl.bEnable := TRUE;

    IF fbAxisCtrl.bEnabled THEN
        fbAxisCtrl.bHome := TRUE;
    END_IF

    IF fbAxisCtrl.bHomed THEN
        fbAxisCtrl.bHome := FALSE;
        eState := AGV_IDLE;
    END_IF

END_CASE

// =========================================================================
// Call axis controller cyclically (regardless of state)
// =========================================================================
fbAxisCtrl(stAxisRef := GVL_Servo.stAxis01);
