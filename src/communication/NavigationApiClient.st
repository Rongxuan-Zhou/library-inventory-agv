// =============================================================================
// NavigationApiClient — HTTP REST Client for Navigation System
// =============================================================================
// Implements the PLC-side HTTP client that communicates with the external
// navigation system at 192.168.3.100:7000.
//
// Uses CODESYS Web Client SL and JSON Utilities SL libraries to construct
// JSON request bodies and parse responses.
//
// Endpoints implemented:
//   POST /api/template/navigating      — Submit navigation task
//   POST /api/template/confirm         — Confirm task template
//   POST /api/navigating/stop          — Abort navigation
//   POST /api/navigating/charging_station/docking   — Dock at charger
//   POST /api/navigating/charging_station/undocking  — Leave charger
//   POST /api/charging/start           — Begin charging
//   POST /api/charging/stop            — End charging
//   POST /api/docking/cancel           — Cancel docking
//   GET  /api/ws                       — WebSocket status (handled separately)
// =============================================================================

FUNCTION_BLOCK NavigationApiClient
VAR_INPUT
    bExecute        : BOOL;             // Rising edge triggers request
    sEndpoint       : STRING(255);      // API path (e.g., '/api/template/navigating')
    sMethod         : STRING(10);       // 'POST' or 'GET'

    // Optional JSON body fields
    sTaskNumber     : STRING(80);       // Task identifier
    sPointName      : STRING(80);       // Waypoint name
    rDockX          : REAL;             // Docking X coordinate
    rDockY          : REAL;             // Docking Y coordinate
    rDockA          : REAL;             // Docking angle
    bIncludeCoords  : BOOL;             // Include x/y/a in JSON body
END_VAR

VAR_OUTPUT
    bDone           : BOOL;             // Request completed successfully
    bBusy           : BOOL;             // Request in progress
    bError          : BOOL;             // Request failed
    nHttpStatus     : INT;              // HTTP response status code
    sResponse       : STRING(1000);     // Response body
END_VAR

VAR
    // CODESYS Web Client SL
    fbHttpClient    : WebClient.HTTPClient;
    fbRequest       : WebClient.HTTPRequest;

    // JSON construction (JSON Utilities SL)
    pJsonData       : POINTER TO JSON.JSONData;
    factory         : JSON.JSONDataFactory;
    fbJBuilder      : JSON.fb_JBuilder;
    jsonWriter      : JSON.JSONByteArrayWriter;
    wsJsonData      : WSTRING(1000);    // JSON output buffer

    // Internal state
    eReqState       : INT;              // 0=idle, 1=building, 2=sending, 3=waiting, 4=done
    rtExecute       : R_TRIG;
    diRootIndex     : DINT;

    // Configuration
    C_BASE_URL      : STRING(80) := 'http://192.168.3.100:7000';
    C_CONTENT_TYPE  : STRING(40) := 'Content-Type: application/json';
    C_TIMEOUT       : TIME := T#5S;
    tTimeout        : TON;
END_VAR

// =========================================================================
// Execution Logic
// =========================================================================
rtExecute(CLK := bExecute);

CASE eReqState OF

0: // IDLE
    bDone := FALSE;
    bBusy := FALSE;
    bError := FALSE;

    IF rtExecute.Q THEN
        bBusy := TRUE;
        eReqState := 1;
    END_IF

1: // BUILD JSON BODY
    // Create JSON document
    pJsonData := factory.Create();
    fbJBuilder(pJsonData := pJsonData, diRootObj => diRootIndex);

    // Add task_number if provided
    IF LEN(sTaskNumber) > 0 THEN
        JSON.JsonObjectAddString(
            pJsonData   := pJsonData,
            diObject    := diRootIndex,
            wsKey       := "task_number",
            wsValue     := STRING_TO_WSTRING(sTaskNumber)
        );
    END_IF

    // Add point name if provided
    IF LEN(sPointName) > 0 THEN
        JSON.JsonObjectAddString(
            pJsonData   := pJsonData,
            diObject    := diRootIndex,
            wsKey       := "point",
            wsValue     := STRING_TO_WSTRING(sPointName)
        );
    END_IF

    // Add docking coordinates if needed
    IF bIncludeCoords THEN
        JSON.JsonObjectAddNumber(
            pJsonData   := pJsonData,
            diObject    := diRootIndex,
            wsKey       := "x",
            lrValue     := REAL_TO_LREAL(rDockX)
        );
        JSON.JsonObjectAddNumber(
            pJsonData   := pJsonData,
            diObject    := diRootIndex,
            wsKey       := "y",
            lrValue     := REAL_TO_LREAL(rDockY)
        );
        JSON.JsonObjectAddNumber(
            pJsonData   := pJsonData,
            diObject    := diRootIndex,
            wsKey       := "a",
            lrValue     := REAL_TO_LREAL(rDockA)
        );
    END_IF

    // Serialize to string
    jsonWriter(
        xExecute    := TRUE,
        pwData      := ADR(wsJsonData),
        udiSize     := SIZEOF(wsJsonData),
        jsonData    := pJsonData^,
        xAsyncMode  := FALSE
    );

    eReqState := 2;

2: // SEND HTTP REQUEST
    fbRequest(
        sUrl            := CONCAT(C_BASE_URL, sEndpoint),
        sMethod         := sMethod,
        sContentType    := 'application/json',
        sBody           := WSTRING_TO_STRING(wsJsonData),
        tTimeout        := C_TIMEOUT
    );

    fbHttpClient.SendRequest(pRequest := ADR(fbRequest));
    tTimeout(IN := TRUE, PT := C_TIMEOUT);
    eReqState := 3;

3: // WAIT FOR RESPONSE
    IF fbHttpClient.xDone THEN
        nHttpStatus := fbHttpClient.iStatusCode;
        sResponse   := fbHttpClient.sResponseBody;
        tTimeout(IN := FALSE);

        IF nHttpStatus >= 200 AND nHttpStatus < 300 THEN
            bDone := TRUE;
        ELSE
            bError := TRUE;
        END_IF

        // Clean up JSON data
        factory.Delete(pJsonData);
        bBusy := FALSE;
        eReqState := 0;

    ELSIF tTimeout.Q THEN
        tTimeout(IN := FALSE);
        factory.Delete(pJsonData);
        bError := TRUE;
        bBusy := FALSE;
        eReqState := 0;
    END_IF

END_CASE
