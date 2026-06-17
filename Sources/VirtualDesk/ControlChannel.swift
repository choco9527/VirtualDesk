import Foundation

final class ControlChannelServer {
    private let path: String
    private let session: WorkspaceSession
    private let queue = DispatchQueue(label: "com.virtualdesk.control.server")
    private let fileManager: FileManager
    private var listenSocket: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String = AgentRuntime.socketPath, session: WorkspaceSession, fileManager: FileManager = .default) {
        self.path = path
        self.session = session
        self.fileManager = fileManager
    }

    func start() throws {
        try stop()

        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }

        listenSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            throw VirtualDeskError.internalError("Failed to create control socket.")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else {
            throw VirtualDeskError.internalError("Control socket path is too long.")
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { src in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), src, maxLength - 1)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenSocket, $0, addressLength) }
        }
        guard bindResult == 0, listen(listenSocket, 8) == 0 else {
            throw VirtualDeskError.internalError("Failed to bind control socket at \(path).")
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: listenSocket, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenSocket >= 0 {
                close(self.listenSocket)
                self.listenSocket = -1
            }
            try? self.fileManager.removeItem(atPath: self.path)
        }
        source = readSource
        readSource.resume()
    }

    func stop() throws {
        source?.cancel()
        source = nil
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }

    private func acceptConnection() {
        let client = accept(listenSocket, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return }

        let data = Data(buffer.prefix(count))
        guard let request = try? JSONDecoder.virtualDesk.decode(BasicCommandRequest.self, from: data) else {
            return
        }

        switch request.method {
        case .stopWorkspace:
            let status = session.stop()
            try? send(status: status, id: request.id, to: client)
        default:
            let payload = VirtualDeskError.invalidCommand("Control channel only supports stop_workspace.").payload
            try? send(error: payload, id: request.id, to: client)
        }
    }

    private func send(status: AgentStatus, id: String, to client: Int32) throws {
        let response = CommandResponse.success(id: id, result: status)
        try write(response, to: client)
    }

    private func send(error: AgentErrorPayload, id: String, to client: Int32) throws {
        let response = CommandResponse<AgentStatus>.failure(id: id, error: error)
        try write(response, to: client)
    }

    private func write<Value: Encodable>(_ value: Value, to client: Int32) throws {
        let data = try JSONEncoder.virtualDeskLine.encode(value)
        _ = data.withUnsafeBytes { bytes in
            Darwin.write(client, bytes.baseAddress, data.count)
        }
    }
}

enum ControlChannelClient {
    static func stopWorkspaceRawResponse(path: String = AgentRuntime.socketPath) throws -> String {
        let data = try sendStopWorkspace(path: path)
        guard let output = String(data: data, encoding: .utf8) else {
            throw VirtualDeskError.internalError("Control socket returned non-UTF8 response.")
        }
        return output
    }

    static func stopWorkspace(path: String = AgentRuntime.socketPath) throws -> AgentStatus {
        let responseData = try sendStopWorkspace(path: path)
        let response = try JSONDecoder.virtualDesk.decode(
            CommandResponse<AgentStatus>.self,
            from: responseData
        )
        if let error = response.error {
            throw VirtualDeskError.internalError(error.message)
        }
        guard let result = response.result else {
            throw VirtualDeskError.internalError("Control socket returned empty result.")
        }
        return result
    }

    private static func sendStopWorkspace(path: String) throws -> Data {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0 else {
            throw VirtualDeskError.internalError("Failed to create control socket client.")
        }
        defer { close(client) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { src in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), src, maxLength - 1)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, addressLength) }
        }
        guard connectResult == 0 else {
            throw VirtualDeskError.workspaceNotRunning
        }

        let request = BasicCommandRequest(id: UUID().uuidString, method: .stopWorkspace)
        let requestData = try JSONEncoder.virtualDeskLine.encode(request)
        _ = requestData.withUnsafeBytes { bytes in
            Darwin.write(client, bytes.baseAddress, requestData.count)
        }

        let responseData = readResponse(from: client)
        guard !responseData.isEmpty else {
            throw VirtualDeskError.internalError("Control socket returned no response.")
        }
        return responseData
    }

    private static func readResponse(from client: Int32) -> Data {
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 {
                break
            }
            response.append(contentsOf: buffer.prefix(count))
        }

        return response
    }
}
