//
//  UltimateLocalWebServer.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-Dependency Embedded HTTP + RFC 6455 WebSocket Server (Network.framework) for Browser Remote & 2-Device Sync.
//

import Foundation
import Network
import CryptoKit

@MainActor
public final class UltimateLocalWebServer: ObservableObject {
    
    public static let shared = UltimateLocalWebServer()
    
    @Published public private(set) var isRunning = false
    @Published public private(set) var serverPort: UInt16 = 8080
    @Published public private(set) var connectedClientsCount: Int = 0
    
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private let serverQueue = DispatchQueue(label: "org.videolan.vlc.ultimate.webserver", qos: .userInitiated)
    
    private init() {}
    
    // MARK: - Server Lifecycle
    
    public func startServer(port: UInt16 = 8080) {
        guard !isRunning else { return }
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            guard let portObj = NWEndpoint.Port(rawValue: port) else { return }
            let nwListener = try NWListener(using: params, on: portObj)
            
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.serverPort = port
                    case .failed, .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            nwListener.start(queue: serverQueue)
            self.listener = nwListener
        } catch {
            self.isRunning = false
        }
    }
    
    public func stopServer() {
        listener?.cancel()
        listener = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        isRunning = false
        connectedClientsCount = 0
    }
    
    // MARK: - Connection & Protocol Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        
        Task { @MainActor in
            self.activeConnections.append(connection)
            self.connectedClientsCount = self.activeConnections.count
        }
        
        readHTTPOrWebSocketData(on: connection)
    }
    
    private func readHTTPOrWebSocketData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let conn = connection, let data = data, !data.isEmpty, error == nil else {
                self?.removeConnection(connection)
                return
            }
            
            // Check if WebSocket frame or raw HTTP request
            if let requestString = String(data: data, encoding: .utf8), requestString.hasPrefix("GET ") || requestString.hasPrefix("POST ") {
                self.handleHTTPRequest(requestString: requestString, on: conn)
            } else {
                // Parse RFC 6455 WebSocket Frame
                self.handleWebSocketFrame(data: data, on: conn)
            }
            
            if !isComplete {
                self.readHTTPOrWebSocketData(on: conn)
            }
        }
    }
    
    private func removeConnection(_ connection: NWConnection?) {
        guard let conn = connection else { return }
        conn.cancel()
        Task { @MainActor in
            self.activeConnections.removeAll { $0 === conn }
            self.connectedClientsCount = self.activeConnections.count
        }
    }
    
    // MARK: - HTTP Request Routing & Web Remote UI
    
    private func handleHTTPRequest(requestString: String, on connection: NWConnection) {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        // 1. WebSocket Upgrade Handshake
        if requestString.contains("Upgrade: websocket") {
            handleWebSocketHandshake(requestString: requestString, on: connection)
            return
        }
        
        // 2. REST API /api/action
        if firstLine.contains("POST /api/action") {
            handleAPIAction(requestString: requestString, on: connection)
            return
        }
        
        // 3. Serve Embedded Modern HTML5 Remote Controller
        let html = getEmbeddedRemoteHTML()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        
        sendData(response.data(using: .utf8)!, on: connection)
    }
    
    private func handleAPIAction(requestString: String, on connection: NWConnection) {
        if requestString.contains("\"action\":\"play_pause\"") {
            Task { @MainActor in
                NotificationCenter.default.post(name: Notification.Name("vlcUltimateTogglePlayPauseRequested"), object: nil)
            }
        } else if requestString.contains("\"action\":\"skip_forward\"") {
            Task { @MainActor in
                NotificationCenter.default.post(name: Notification.Name("vlcUltimateSeekRelativeRequested"), object: nil, userInfo: ["offset": 10.0])
            }
        } else if requestString.contains("\"action\":\"skip_backward\"") {
            Task { @MainActor in
                NotificationCenter.default.post(name: Notification.Name("vlcUltimateSeekRelativeRequested"), object: nil, userInfo: ["offset": -10.0])
            }
        }
        
        let jsonResponse = "{\"status\":\"ok\"}"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(jsonResponse.utf8.count)\r
        Connection: close\r
        \r
        \(jsonResponse)
        """
        sendData(response.data(using: .utf8)!, on: connection)
    }
    
    // MARK: - RFC 6455 WebSocket Handshake & Framing
    
    private func handleWebSocketHandshake(requestString: String, on connection: NWConnection) {
        var secWebSocketKey = ""
        let lines = requestString.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    secWebSocketKey = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        guard !secWebSocketKey.isEmpty else { return }
        let magicString = secWebSocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let sha1 = Insecure.SHA1.hash(data: magicString.data(using: .utf8)!)
        let acceptKey = Data(sha1).base64EncodedString()
        
        let handshakeResponse = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r
        """
        
        sendData(handshakeResponse.data(using: .utf8)!, on: connection)
    }
    
    private func handleWebSocketFrame(data: Data, on connection: NWConnection) {
        guard data.count >= 2 else { return }
        let firstByte = data[0]
        let secondByte = data[1]
        
        let opcode = firstByte & 0x0F
        let isMasked = (secondByte & 0x80) != 0
        var payloadLength = UInt64(secondByte & 0x7F)
        var offset = 2
        
        if payloadLength == 126 {
            guard data.count >= 4 else { return }
            payloadLength = UInt64(data[2]) << 8 | UInt64(data[3])
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return }
            offset = 10
        }
        
        var maskingKey: [UInt8] = [0, 0, 0, 0]
        if isMasked {
            guard data.count >= offset + 4 else { return }
            maskingKey = [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
            offset += 4
        }
        
        guard data.count >= offset + Int(payloadLength) else { return }
        var unmaskedData = Data(count: Int(payloadLength))
        for i in 0..<Int(payloadLength) {
            let byte = data[offset + i]
            unmaskedData[i] = byte ^ maskingKey[i % 4]
        }
        
        // Opcode 0x1: UTF-8 Text Frame
        if opcode == 0x01, let text = String(data: unmaskedData, encoding: .utf8) {
            handleClientSyncMessage(text: text, on: connection)
        }
    }
    
    // MARK: - Millisecond Clock Synchronization for 2-Device Sync
    
    private func handleClientSyncMessage(text: String, on connection: NWConnection) {
        // NTP-like timestamp ping: {"type":"sync_ping","client_send_ts":123456789}
        if text.contains("sync_ping") {
            let now = Date().timeIntervalSince1970 * 1000.0 // ms
            let response = "{\"type\":\"sync_pong\",\"server_ts\":\(now)}"
            sendWebSocketText(response, on: connection)
        }
    }
    
    public func broadcastSyncCommand(action: String, targetTimestamp: TimeInterval) {
        let json = "{\"type\":\"sync_action\",\"action\":\"\(action)\",\"timestamp\":\(targetTimestamp)}"
        for conn in activeConnections {
            sendWebSocketText(json, on: conn)
        }
    }
    
    private func sendWebSocketText(_ text: String, on connection: NWConnection) {
        let payload = text.data(using: .utf8)!
        var frame = Data()
        frame.append(0x81) // FIN + Text Opcode
        
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= 65535 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        }
        frame.append(payload)
        sendData(frame, on: connection)
    }
    
    private func sendData(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
    
    // MARK: - Embedded HTML5 Remote Control UI
    
    private func getEmbeddedRemoteHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <title>VLC Ultimate Remote</title>
            <style>
                body { background: #0B0C10; color: #FFF; font-family: -apple-system, sans-serif; text-align: center; padding: 24px; }
                h1 { color: #66FCF1; font-size: 20px; letter-spacing: 1px; }
                .btn { background: #1F2833; border: 1px solid #45A29E; color: #FFF; padding: 16px 28px; border-radius: 12px; font-size: 18px; margin: 8px; cursor: pointer; }
                .btn:active { background: #66FCF1; color: #000; }
                .badge { background: #FF6B35; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: bold; }
            </style>
        </head>
        <body>
            <h1>VLC ULTIMATE WORKSTATION</h1>
            <p><span class="badge">WI-FI REMOTE CONNECTED</span></p>
            <div style="margin-top: 40px;">
                <button class="btn" onclick="sendAction('skip_backward')">-10s</button>
                <button class="btn" style="background:#45A29E;" onclick="sendAction('play_pause')">PLAY / PAUSE</button>
                <button class="btn" onclick="sendAction('skip_forward')">+10s</button>
            </div>
            <script>
                function sendAction(act) {
                    fetch('/api/action', { method: 'POST', body: JSON.stringify({ action: act }) });
                }
            </script>
        </body>
        </html>
        """
    }
}
