import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError.malformedResponse }
        return (data, http)
    }
}

public enum NotionError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case http(status: Int, body: String)
    case malformedResponse
    /// Anything outside the Notion API itself (network down, local store failure).
    case other(String)
}

/// Where the app writes in the user's workspace, created once by `setUpWorkspace`.
public struct NotionConfig: Codable, Equatable, Sendable {
    public var dataSourceId: String
    public var recapsPageId: String

    public init(dataSourceId: String, recapsPageId: String) {
        self.dataSourceId = dataSourceId
        self.recapsPageId = recapsPageId
    }
}

public enum NotionPageId {
    /// Accepts a Notion page URL or a bare id; returns the dashed UUID form.
    public static func parse(_ urlOrId: String) -> String? {
        let path = urlOrId.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        let compact = path.replacingOccurrences(of: "-", with: "")
        guard let match = compact.firstMatch(of: /[0-9a-fA-F]{32}$/) else { return nil }
        let hex = Array(match.output.lowercased())
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }.joined(separator: "-")
    }
}

public struct NotionClient: Sendable {
    public static let apiVersion = "2026-03-11"
    private static let baseURL = URL(string: "https://api.notion.com")!

    private let token: String
    private let transport: any HTTPTransport

    public init(token: String, transport: any HTTPTransport) {
        self.token = token
        self.transport = transport
    }

    /// Creates the « Marches » database and the « Récaps hebdo » page under the shared parent page.
    public func setUpWorkspace(parentPageId: String) async throws -> NotionConfig {
        let database = try await send("POST", "/v1/databases", NotionPayloads.databaseBody(parentPageId: parentPageId))
        guard let dataSources = database["data_sources"] as? [[String: Any]],
              let dataSourceId = dataSources.first?["id"] as? String else { throw NotionError.malformedResponse }
        let recaps = try await createPage(NotionPayloads.childPageBody(parentPageId: parentPageId,
                                                                       title: NotionPayloads.recapsPageTitle))
        return NotionConfig(dataSourceId: dataSourceId, recapsPageId: recaps)
    }

    public func createSessionPage(_ session: WalkSession, in config: NotionConfig, calendar: Calendar) async throws -> String {
        try await createPage(NotionPayloads.sessionPageBody(session, dataSourceId: config.dataSourceId, calendar: calendar))
    }

    public func createRecapPage(_ summary: WeeklySummary, in config: NotionConfig) async throws -> String {
        try await createPage(NotionPayloads.recapPageBody(summary, recapsPageId: config.recapsPageId))
    }

    /// The session's row if it already exists (e.g. created before a lost response), matched on the « ID » column.
    public func findSessionPage(_ id: UUID, in config: NotionConfig) async throws -> String? {
        let body: [String: Any] = ["filter": ["property": "ID", "rich_text": ["equals": id.uuidString]], "page_size": 1]
        let result = try await send("POST", "/v1/data_sources/\(config.dataSourceId)/query", body)
        return ((result["results"] as? [[String: Any]])?.first)?["id"] as? String
    }

    public func trashPage(_ pageId: String) async throws {
        _ = try await send("PATCH", "/v1/pages/\(pageId)", ["in_trash": true])
    }

    private func createPage(_ body: [String: Any]) async throws -> String {
        guard let id = try await send("POST", "/v1/pages", body)["id"] as? String else {
            throw NotionError.malformedResponse
        }
        return id
    }

    private func send(_ method: String, _ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(request)
        try Self.check(status: response.statusCode, data: data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func check(status: Int, data: Data) throws {
        switch status {
        case 200..<300: return
        case 401: throw NotionError.unauthorized
        case 429: throw NotionError.rateLimited
        default: throw NotionError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }
}
