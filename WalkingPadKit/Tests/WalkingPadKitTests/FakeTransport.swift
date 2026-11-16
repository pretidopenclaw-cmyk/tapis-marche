import Foundation
import Synchronization
@testable import WalkingPadKit

/// Records every request and answers with queued (status, JSON) responses; default 200 `{"id": "page-N"}`.
final class FakeTransport: HTTPTransport {
    struct Sent {
        let method: String
        let path: String
        let headers: [String: String]
        let json: [String: Any]
    }

    private let state = Mutex<(responses: [(Int, String)], sent: [Sent])>(([], []))
    /// Simulated network latency, to let concurrent callers interleave.
    let latency: Duration

    init(latency: Duration = .zero) {
        self.latency = latency
    }

    func enqueue(_ status: Int, _ body: String) {
        state.withLock { $0.responses.append((status, body)) }
    }

    var sent: [Sent] { state.withLock { $0.sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if latency > .zero { try await Task.sleep(for: latency) }
        let json = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let (status, body) = state.withLock { state -> (Int, String) in
            state.sent.append(Sent(method: request.httpMethod ?? "GET", path: request.url!.path,
                                   headers: request.allHTTPHeaderFields ?? [:], json: json))
            return state.responses.isEmpty ? (200, #"{"id": "page-\#(state.sent.count)"}"#)
                                           : state.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

extension FakeTransport.Sent: @unchecked Sendable {}
