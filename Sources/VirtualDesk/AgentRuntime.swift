import Darwin
import Foundation

struct AgentRuntime {
    static let lockPath = "/tmp/virtualdesk-agent.lock"
    static let statePath = "/tmp/virtualdesk-agent-state.json"
}

final class AgentLock {
    private let fileDescriptor: Int32
    private let path: String

    private init(fileDescriptor: Int32, path: String) {
        self.fileDescriptor = fileDescriptor
        self.path = path
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    static func acquire(path: String = AgentRuntime.lockPath) throws -> AgentLock {
        let fileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw VirtualDeskError.lockUnavailable("Could not open lock file at \(path).")
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            throw VirtualDeskError.agentAlreadyRunning(path)
        }

        let pid = "\(getpid())\n"
        ftruncate(fileDescriptor, 0)
        lseek(fileDescriptor, 0, SEEK_SET)
        _ = pid.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }

        return AgentLock(fileDescriptor: fileDescriptor, path: path)
    }

    static func isHeld(path: String = AgentRuntime.lockPath) -> Bool {
        let fileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            return false
        }

        let locked = flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0
        if !locked {
            flock(fileDescriptor, LOCK_UN)
        }

        close(fileDescriptor)
        return locked
    }

    static func readPID(path: String = AgentRuntime.lockPath) -> Int32 {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }

        return pid
    }
}

struct AgentStateStore {
    let path: String

    init(path: String = AgentRuntime.statePath) {
        self.path = path
    }

    func save(_ status: AgentStatus) throws {
        let data = try JSONEncoder.virtualDesk.encode(status)
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }

    func load() -> AgentStatus? {
        let url = URL(fileURLWithPath: path)

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder.virtualDesk.decode(AgentStatus.self, from: data)
    }

    func loadRawString() -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
