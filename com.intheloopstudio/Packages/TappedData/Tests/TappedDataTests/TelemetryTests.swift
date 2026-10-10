import Foundation
import Network
import Synchronization
import Testing
@testable import TappedData

@Suite("Telemetry settings")
struct TelemetrySettingsTests {
    let app = AppInfo(version: "2.1.0", build: "42", deviceModel: "iPhone18,1", osVersion: "26.0.0")

    @Test func noKeyIsANoOp() {
        #expect(TelemetrySettings.make(config: TappedConfig(postHogAPIKey: ""), app: app, environment: [:]) == nil)
    }

    @Test func mockModeIsANoOp() {
        let config = TappedConfig(postHogAPIKey: "phc_test")
        #expect(TelemetrySettings.make(config: config, app: app, environment: ["TAPPED_MOCK": "1"]) == nil)
    }

    @Test func exportsToThePostHogProjectsTracesEndpoint() throws {
        let config = TappedConfig(postHogAPIKey: "phc_test", postHogHost: "https://eu.i.posthog.com")
        let settings = try #require(TelemetrySettings.make(config: config, app: app, environment: [:]))
        #expect(settings.tracesEndpoint == URL(string: "https://eu.i.posthog.com/i/v1/traces"))
        #expect(settings.headers == ["Authorization": "Bearer phc_test"])
        #expect(settings.resource == [
            "service.name": "tapped-ios",
            "service.version": "2.1.0",
            "app.build": "42",
            "device.model.identifier": "iPhone18,1",
            "os.name": "iOS",
            "os.version": "26.0.0",
        ])
        #expect(settings.spanHosts == ["api.tapped.ai"])
        #expect(settings.propagationHosts == ["api.tapped.ai"])
    }
}

@Suite("OpenTelemetry export")
struct OpenTelemetryExportTests {
    @Test func exportsSpansAndPropagatesTraceparentToALocalEndpoint() async throws {
        let server = try await LocalHTTPServer.start()
        let telemetry = OpenTelemetryTracing(settings: TelemetrySettings(
            tracesEndpoint: try #require(URL(string: "http://127.0.0.1:\(server.port)/i/v1/traces")),
            headers: ["Authorization": "Bearer phc_test"],
            resource: ["service.name": TelemetrySettings.serviceName],
            spanHosts: ["localhost"],
            propagationHosts: ["localhost"]
        ))

        let api = URLRequest(url: try #require(URL(string: "http://localhost:\(server.port)/v1/ping")))
        _ = try await URLSession.shared.data(for: api)
        let other = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(server.port)/untraced")))
        _ = try await URLSession.shared.data(for: other)
        await telemetry.record([TelemetrySpan(name: "launch.test", start: .now.addingTimeInterval(-0.5), end: .now)])

        let ping = try #require(server.requests.first { $0.path == "/v1/ping" })
        let traceparent = try #require(ping.headers["traceparent"])
        let parts = traceparent.split(separator: "-").map(String.init)
        try #require(parts.count == 4)
        #expect(parts[0] == "00")
        #expect(parts[1].count == 32)
        #expect(parts[2].count == 16)
        #expect(server.requests.first { $0.path == "/untraced" }?.headers["traceparent"] == nil)

        let traceId = try #require(Data(hex: parts[1]))
        var exported = Data()
        for _ in 0..<100 {
            telemetry.flush()
            let exports = server.requests.filter { $0.path == "/i/v1/traces" }
            exported = try exports.reduce(into: Data()) { $0.append(try LocalHTTPServer.gunzip($1.body)) }
            if exported.range(of: traceId) != nil, exported.range(of: Data("launch.test".utf8)) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let export = try #require(server.requests.first { $0.path == "/i/v1/traces" })
        #expect(export.method == "POST")
        #expect(export.headers["authorization"] == "Bearer phc_test")
        #expect(export.headers["content-type"] == "application/x-protobuf")
        #expect(exported.range(of: Data("tapped-ios".utf8)) != nil)
        #expect(exported.range(of: Data("launch.test".utf8)) != nil)
        // The client span for /v1/ping carries the trace id it propagated.
        #expect(exported.range(of: traceId) != nil)
    }
}

/// Minimal HTTP/1.1 server on a random local port that records each request and answers `200`.
// Mutable state is behind `Mutex`; the listener is only touched from `queue`.
final class LocalHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        /// Lowercased names.
        var headers: [String: String]
        var body: Data
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalHTTPServer")
    private let received = Mutex<[Request]>([])

    var requests: [Request] { received.withLock { $0 } }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    private init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    static func start() async throws -> LocalHTTPServer {
        let server = try LocalHTTPServer()
        server.listener.newConnectionHandler = { [server] connection in server.handle(connection) }
        server.listener.start(queue: server.queue)
        for _ in 0..<100 where server.port == 0 { try await Task.sleep(for: .milliseconds(20)) }
        try #require(server.port != 0)
        return server
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                received.withLock { $0.append(request) }
                let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    static func parse(_ data: Data) -> Request? {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<headEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = data[headEnd.upperBound...]
        let length = headers["content-length"].flatMap { Int($0) } ?? 0
        guard body.count >= length else { return nil }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body.prefix(length)))
    }

    /// Strips the 10-byte gzip header and 8-byte trailer, then inflates the raw DEFLATE stream.
    static func gunzip(_ data: Data) throws -> Data {
        guard data.count > 18, data.prefix(2) == Data([0x1F, 0x8B]) else { return data }
        return try (Data(data.dropFirst(10).dropLast(8)) as NSData).decompressed(using: .zlib) as Data
    }
}

private extension Data {
    init?(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
