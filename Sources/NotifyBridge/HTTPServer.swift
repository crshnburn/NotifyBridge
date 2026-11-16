import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]  // keys lowercased
    let body: Data
}

struct HTTPResponse {
    let status: Int
    let json: [String: Any]

    static func ok(_ json: [String: Any] = ["status": "ok"]) -> HTTPResponse {
        HTTPResponse(status: 200, json: json)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, json: ["status": "error", "error": message])
    }
}

/// A deliberately tiny HTTP/1.1 server: one request per connection, no keep-alive.
final class HTTPServer {
    typealias Handler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    static let maxRequestSize = 1_048_576

    private let listener: NWListener
    private let queue = DispatchQueue(label: "notifybridge.http")
    private let handler: Handler

    init(host: String, port: UInt16, handler: @escaping Handler) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NWError.posix(.EINVAL)
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        self.listener = try NWListener(using: params)
        self.handler = handler
    }

    func start(onState: @escaping (NWListener.State) -> Void) {
        listener.stateUpdateHandler = onState
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > Self.maxRequestSize {
                self.send(.error(413, "request too large"), on: connection)
                return
            }

            switch Self.parse(buffer) {
            case .complete(let request):
                self.handler(request) { response in
                    self.send(response, on: connection)
                }
            case .invalid(let reason):
                self.send(.error(400, reason), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: response.json, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let head = """
            HTTP/1.1 \(response.status) \(Self.reason(response.status))\r
            Content-Type: application/json\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    // MARK: - Parsing

    private enum ParseResult {
        case incomplete
        case invalid(String)
        case complete(HTTPRequest)
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: buffer.subdata(in: 0..<headerEnd.lowerBound), encoding: .utf8) else {
            return .invalid("malformed headers")
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid("malformed request line") }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        var contentLength = 0
        if let raw = headers["content-length"] {
            guard let value = Int(raw), value >= 0 else { return .invalid("invalid Content-Length") }
            contentLength = value
        }
        if contentLength > maxRequestSize { return .invalid("request too large") }

        let bodyStart = headerEnd.upperBound
        guard buffer.count >= bodyStart + contentLength else { return .incomplete }

        let target = String(requestLine[1])
        let components = URLComponents(string: "http://localhost" + target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        return .complete(HTTPRequest(
            method: requestLine[0].uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        ))
    }
}
