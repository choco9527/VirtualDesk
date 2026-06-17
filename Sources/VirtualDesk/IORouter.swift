import Foundation

final class IORouter {
    private let outputQueue = DispatchQueue(label: "com.virtualdesk.agent.output")
    private var inputTask: Task<Void, Never>?

    func startListening(onCommand: @escaping (Data) -> Void) {
        inputTask = Task.detached {
            do {
                for try await line in FileHandle.standardInput.bytes.lines {
                    guard let data = line.data(using: .utf8) else {
                        AgentLog.error("Received non-UTF8 input line.")
                        continue
                    }

                    onCommand(data)
                }
            } catch {
                AgentLog.error("stdin closed: \(error.localizedDescription)")
            }
        }
    }

    func send<Result: Encodable>(_ response: CommandResponse<Result>) {
        write(response)
    }

    func sendFailure(id: String, error: AgentErrorPayload) {
        send(CommandResponse<EmptyParams>.failure(id: id, error: error))
    }

    func sendEvent<Data: Encodable>(_ event: AgentEvent<Data>) {
        write(event)
    }

    private func write<Value: Encodable>(_ value: Value) {
        outputQueue.async {
            do {
                let data = try JSONEncoder.virtualDeskLine.encode(value)
                guard var line = String(data: data, encoding: .utf8) else {
                    AgentLog.error("Failed to encode NDJSON line.")
                    return
                }

                line.append("\n")
                FileHandle.standardOutput.write(Data(line.utf8))
            } catch {
                AgentLog.error("Failed to write response: \(error.localizedDescription)")
            }
        }
    }
}
