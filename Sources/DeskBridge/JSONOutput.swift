import Foundation

extension JSONEncoder {
    static var deskBridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension JSONDecoder {
    static var deskBridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum JSONOutput {
    static func print<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder.deskBridge.encode(value)

        guard let output = String(data: data, encoding: .utf8) else {
            throw DeskBridgeError.jsonEncodingFailed
        }

        Swift.print(output)
    }
}
