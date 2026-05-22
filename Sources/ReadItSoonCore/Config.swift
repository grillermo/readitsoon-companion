import Foundation

public protocol ConfigStore {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

public struct LocalConfigStore: ConfigStore {
    public init() {}

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public struct Config: Codable, Equatable {
    public var savePath: String

    public init(savePath: String) {
        self.savePath = savePath
    }

    enum CodingKeys: String, CodingKey {
        case savePath = "save_path"
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".readitsoon-companion.json")
    }

    public static func load(
        from fileURL: URL = defaultFileURL,
        store: any ConfigStore = LocalConfigStore()
    ) -> Config? {
        guard let data = try? store.read(from: fileURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    public static func save(
        _ config: Config,
        to fileURL: URL = defaultFileURL,
        store: any ConfigStore = LocalConfigStore()
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(config) else { return }
        try? store.write(data, to: fileURL)
    }
}
