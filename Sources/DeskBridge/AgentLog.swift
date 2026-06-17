import Foundation

enum AgentLog {
    static func info(_ message: String) {
        write("Info: \(message)")
    }

    static func warning(_ message: String) {
        write("Warning: \(message)")
    }

    static func error(_ message: String) {
        write("Error: \(message)")
    }

    private static func write(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
