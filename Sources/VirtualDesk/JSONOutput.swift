import Foundation

extension JSONEncoder {
    static var virtualDesk: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static var virtualDeskLine: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension JSONDecoder {
    static var virtualDesk: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum JSONOutput {
    static func print<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder.virtualDesk.encode(value)

        guard let output = String(data: data, encoding: .utf8) else {
            throw VirtualDeskError.jsonEncodingFailed
        }

        Swift.print(output)
    }
}
