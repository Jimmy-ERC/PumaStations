import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Configuration

/// Project URL and publishable key, read from `Supabase.plist` (not versioned, see README).
struct SupabaseConfig: Sendable {
    let url: URL
    let publishableKey: String

    init?(urlString: String, publishableKey: String) {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil, !key.isEmpty else { return nil }
        self.url = url
        self.publishableKey = key
    }

    static func load(from bundle: Bundle = .main) -> SupabaseConfig? {
        guard let fileURL = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = plist["SUPABASE_URL"] as? String,
              let key = plist["SUPABASE_PUBLISHABLE_KEY"] as? String else { return nil }
        return SupabaseConfig(urlString: urlString, publishableKey: key)
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case notAuthenticated
    case inactiveAccount
    case profileNotFound
    case network(String)
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Falta configurar Supabase. Crea el archivo Supabase.plist como indica el README."
        case .invalidCredentials:
            return "Correo o contraseña incorrectos."
        case .notAuthenticated:
            return "Tu sesión expiró. Inicia sesión de nuevo."
        case .inactiveAccount:
            return "Tu cuenta está desactivada. Contacta a la gerencia general."
        case .profileNotFound:
            return "Tu usuario no tiene un perfil asignado. Contacta a la gerencia general."
        case .network(let message):
            return "No se pudo conectar con el servidor: \(message)"
        case .server(_, let message):
            return message
        }
    }
}

// MARK: - Client

/// Minimal Supabase client over URLSession: Auth (email + password) and the REST API (PostgREST).
actor SupabaseClient {
    private struct Session {
        let accessToken: String
        let refreshToken: String
        let userID: UUID
        let expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: UUID
        }

        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    /// Error bodies of Auth (`msg`, `error_description`) and PostgREST (`message`).
    private struct ErrorResponse: Decodable {
        let message: String?
        let msg: String?
        let errorDescription: String?
        let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case message
            case msg
            case errorDescription = "error_description"
            case errorCode = "error_code"
        }
    }

    /// PostgREST returns at most 1000 rows per request.
    private static let pageSize = 1_000

    private let config: SupabaseConfig
    private let urlSession: URLSession
    private var session: Session?

    init(config: SupabaseConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    // MARK: Auth

    /// Signs in with email and password and returns the id of the user.
    @discardableResult
    func signIn(email: String, password: String) async throws -> UUID {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let request = makeRequest(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], method: "POST", body: body)
        let (data, status) = try await send(request)
        guard status == 200 else {
            let code = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.errorCode
            if code == "invalid_credentials" { throw SupabaseError.invalidCredentials }
            throw Self.decodeError(data, status: status)
        }
        let newSession = try Self.makeSession(from: data)
        session = newSession
        return newSession.userID
    }

    func signOut() async {
        guard let current = session else { return }
        session = nil
        var request = makeRequest(path: "auth/v1/logout", method: "POST")
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await send(request)
    }

    /// Returns a valid access token, refreshing it when it is about to expire.
    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = session else { throw SupabaseError.notAuthenticated }
        if !forceRefresh && current.expiresAt.timeIntervalSinceNow > 60 {
            return current.accessToken
        }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
        let request = makeRequest(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], method: "POST", body: body)
        let (data, status) = try await send(request)
        guard status == 200 else {
            session = nil
            throw SupabaseError.notAuthenticated
        }
        let refreshed = try Self.makeSession(from: data)
        session = refreshed
        return refreshed.accessToken
    }

    private static func makeSession(from data: Data) throws -> Session {
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Session(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userID: response.user.id,
            expiresAt: Date().addingTimeInterval(response.expiresIn)
        )
    }

    // MARK: REST

    /// Reads every row the user is allowed to see, page by page.
    func selectAll<T: Decodable>(_ type: T.Type, from table: String) async throws -> [T] {
        var rows: [T] = []
        while true {
            let query = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "id"),
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "offset", value: String(rows.count))
            ]
            let data = try await sendAuthorized(path: "rest/v1/\(table)", query: query, method: "GET")
            let page = try RemoteCoding.decoder.decode([T].self, from: data)
            rows.append(contentsOf: page)
            if page.count < Self.pageSize { return rows }
        }
    }

    /// Inserts the rows. Rows that already exist are skipped, so the call can be retried safely.
    func insert<T: Encodable>(_ rows: [T], into table: String) async throws {
        guard !rows.isEmpty else { return }
        let body = try RemoteCoding.encoder.encode(rows)
        try await sendAuthorized(
            path: "rest/v1/\(table)",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            body: body,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }

    func update<T: Encodable>(_ row: T, in table: String, id: UUID) async throws {
        let body = try RemoteCoding.encoder.encode(row)
        try await sendAuthorized(
            path: "rest/v1/\(table)",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            method: "PATCH",
            body: body,
            prefer: "return=minimal"
        )
    }

    func delete(from table: String, id: UUID) async throws {
        try await sendAuthorized(
            path: "rest/v1/\(table)",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            method: "DELETE",
            prefer: "return=minimal"
        )
    }

    /// Calls a database function exposed by the API.
    func rpc<T: Encodable>(_ function: String, params: T) async throws {
        let body = try RemoteCoding.encoder.encode(params)
        try await sendAuthorized(path: "rest/v1/rpc/\(function)", method: "POST", body: body)
    }

    // MARK: Transport

    @discardableResult
    private func sendAuthorized(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        var request = makeRequest(path: path, query: query, method: method, body: body)
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        var token = try await accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, status) = try await send(request)

        if status == 401 {
            // The token expired earlier than expected: refresh it and try once more.
            token = try await accessToken(forceRefresh: true)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            (data, status) = try await send(request)
        }
        guard (200..<300).contains(status) else {
            throw Self.decodeError(data, status: status)
        }
        return data
    }

    private func makeRequest(path: String, query: [URLQueryItem] = [], method: String, body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        var request = URLRequest(url: components?.url ?? config.url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw SupabaseError.network(error.localizedDescription)
        }
    }

    private static func decodeError(_ data: Data, status: Int) -> SupabaseError {
        let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        let message = body?.message ?? body?.msg ?? body?.errorDescription ?? "Error del servidor (\(status))."
        return .server(status: status, message: message)
    }
}

// MARK: - JSON

enum RemoteCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(fromTimestamp: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp: \(text)")
            }
            return date
        }
        return decoder
    }()

    static func timestamp(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Parses a Postgres `timestamptz` such as `2026-10-08T20:00:00.922997+00:00`.
    static func date(fromTimestamp text: String) -> Date? {
        var value = text
        // ISO8601DateFormatter does not accept microseconds: drop the fractional part.
        if let dot = value.firstIndex(of: ".") {
            let end = value[dot...].dropFirst().firstIndex { !$0.isNumber } ?? value.endIndex
            value.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
