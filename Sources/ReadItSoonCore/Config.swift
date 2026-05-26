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
    public var session: AuthSession?

    public init(savePath: String, session: AuthSession? = nil) {
        self.savePath = savePath
        self.session = session
    }

    public func signedOut() -> Config {
        Config(savePath: savePath)
    }

    enum CodingKeys: String, CodingKey {
        case savePath = "save_path"
        case session
        case email
        case authToken = "auth_token"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savePath = try container.decodeIfPresent(String.self, forKey: .savePath) ?? ""

        if let session = try container.decodeIfPresent(AuthSession.self, forKey: .session) {
            self.session = session
            return
        }

        if
            let email = try container.decodeIfPresent(String.self, forKey: .email),
            let token = try container.decodeIfPresent(String.self, forKey: .authToken),
            !email.isEmpty,
            !token.isEmpty
        {
            session = AuthSession(email: email, token: token)
        } else {
            session = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(savePath, forKey: .savePath)
        try container.encodeIfPresent(session, forKey: .session)
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

public struct AuthSession: Codable, Equatable {
    public var email: String
    public var token: String

    public init(email: String, token: String) {
        self.email = email
        self.token = token
    }
}
