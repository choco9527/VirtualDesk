import Foundation

struct ConfigurationStore {
    let path: String

    init(path: String = AgentRuntime.configPath) {
        self.path = path
    }

    func load() -> VirtualDeskUserConfig? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder.virtualDesk.decode(VirtualDeskUserConfig.self, from: data)
    }

    func save(_ config: VirtualDeskUserConfig) throws {
        let data = try JSONEncoder.virtualDesk.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }
}
