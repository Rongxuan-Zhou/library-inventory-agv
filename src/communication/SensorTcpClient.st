// =============================================================================
// SensorTcpClient — TCP Socket Client for RFID & Vision Sensors
// =============================================================================
// Manages TCP connections to the RFID reader and vision camera.
// Provides request/response pattern with timeout and reconnection logic.
//
// The RFID reader and vision camera communicate via raw TCP:
//   1. PLC sends a trigger command (scan request)
//   2. Device performs operation (RFID read / image capture + OCR)
//   3. Device returns result data
//   4. PLC parses result and updates inventory count
//
// Connection monitoring:
//   HMI_RFID_ConnectionActive   — RFID reader TCP alive
//   HMI_Vision_ConnectionActive — Vision camera TCP alive
// =============================================================================

FUNCTION_BLOCK SensorTcpClient
VAR_INPUT
    sServerIP       : STRING(15);       // Device IP address
    uiServerPort    : UINT;             // Device TCP port
    bConnect        : BOOL;             // Enable connection
    bSendRequest    : BOOL;             // Trigger data request
    sSendData       : STRING(255);      // Request payload
END_VAR

VAR_OUTPUT
    bConnected      : BOOL;             // TCP connection established
    bDataReady      : BOOL;             // Response received
    bError          : BOOL;             // Communication error
    sRecvData       : STRING(2000);     // Received response data
    nItemCount      : INT;              // Parsed: number of items detected
    nErrorCode      : DWORD;            // TCP error code
END_VAR

VAR
    // CODESYS TCP library function blocks
    fbClient        : NBS.TCP_Client;
    fbRead          : NBS.TCP_Read;
    fbWrite         : NBS.TCP_Write;

    // Connection management
    eConnState      : INT;              // 0=disconnected, 1=connecting, 2=connected
    tReconnect      : TON;              // Reconnection delay timer
    nReconnectCount : INT;              // Reconnection attempt counter

    // Request/Response state
    eReqState       : INT;              // 0=idle, 1=sending, 2=waiting, 3=done
    rtSendReq       : R_TRIG;
    tRespTimeout    : TON;

    // Buffers
    abyRecvBuffer   : ARRAY[0..2047] OF BYTE;
    uiBytesRecv     : UINT;

    // Constants
    C_RECONNECT_DELAY : TIME := T#3S;
    C_RESP_TIMEOUT    : TIME := T#5S;
    C_MAX_RECONNECT   : INT  := 5;
END_VAR

// =========================================================================
// Connection Management
// =========================================================================
CASE eConnState OF

0: // DISCONNECTED
    bConnected := FALSE;
    IF bConnect THEN
        fbClient(
            xEnable     := TRUE,
            sAddr       := sServerIP,
            uiPort      := uiServerPort
        );
        eConnState := 1;
    END_IF

1: // CONNECTING
    fbClient(xEnable := TRUE);

    IF fbClient.xActive THEN
        eConnState := 2;
        bConnected := TRUE;
        nReconnectCount := 0;
    ELSIF fbClient.xError THEN
        fbClient(xEnable := FALSE);
        nReconnectCount := nReconnectCount + 1;

        IF nReconnectCount < C_MAX_RECONNECT THEN
            tReconnect(IN := TRUE, PT := C_RECONNECT_DELAY);
            IF tReconnect.Q THEN
                tReconnect(IN := FALSE);
                eConnState := 0;    // Retry
            END_IF
        ELSE
            bError := TRUE;         // Give up after max retries
        END_IF
    END_IF

2: // CONNECTED
    bConnected := TRUE;

    // Monitor connection health
    IF NOT fbClient.xActive THEN
        bConnected := FALSE;
        eConnState := 0;           // Connection lost, auto-reconnect
    END_IF

END_CASE

// =========================================================================
// Request / Response Handling
// =========================================================================
rtSendReq(CLK := bSendRequest);

CASE eReqState OF

0: // IDLE
    bDataReady := FALSE;

    IF rtSendReq.Q AND bConnected THEN
        eReqState := 1;
    END_IF

1: // SENDING REQUEST
    fbWrite(
        xExecute    := TRUE,
        hConnection := fbClient.hConnection,
        pData       := ADR(sSendData),
        udiSize     := INT_TO_UDINT(LEN(sSendData))
    );

    IF fbWrite.xDone THEN
        fbWrite(xExecute := FALSE);
        tRespTimeout(IN := TRUE, PT := C_RESP_TIMEOUT);
        eReqState := 2;
    ELSIF fbWrite.xError THEN
        fbWrite(xExecute := FALSE);
        bError := TRUE;
        eReqState := 0;
    END_IF

2: // WAITING FOR RESPONSE
    fbRead(
        xEnable     := TRUE,
        hConnection := fbClient.hConnection,
        pData       := ADR(abyRecvBuffer),
        udiSize     := SIZEOF(abyRecvBuffer)
    );

    IF fbRead.udiCount > 0 THEN
        // Data received
        fbRead(xEnable := FALSE);
        tRespTimeout(IN := FALSE);

        uiBytesRecv := UDINT_TO_UINT(fbRead.udiCount);
        // Copy to output string (simplified — real impl handles encoding)
        MEMUtils.MemCpy(
            pDest := ADR(sRecvData),
            pSrc  := ADR(abyRecvBuffer),
            udiCount := MIN(fbRead.udiCount, SIZEOF(sRecvData) - 1)
        );

        // Parse item count from response
        // (actual parsing depends on device protocol — simplified here)
        nItemCount := ParseItemCount(sRecvData);

        bDataReady := TRUE;
        eReqState := 0;

    ELSIF tRespTimeout.Q THEN
        // Timeout — no response from sensor
        fbRead(xEnable := FALSE);
        tRespTimeout(IN := FALSE);
        bError := TRUE;
        nItemCount := 0;
        eReqState := 0;
    END_IF

END_CASE

// =========================================================================
// Disconnect handling
// =========================================================================
IF NOT bConnect THEN
    fbClient(xEnable := FALSE);
    bConnected := FALSE;
    eConnState := 0;
    eReqState := 0;
END_IF
