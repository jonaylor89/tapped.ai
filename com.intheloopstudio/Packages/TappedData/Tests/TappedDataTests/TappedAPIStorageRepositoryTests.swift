import Foundation
import Synchronization
import Testing
@testable import TappedData

@Suite("Tapped API storage uploads", .serialized)
struct TappedAPIStorageRepositoryTests {
    static let ticket = """
    {"uploadUrl":"https://acct.r2.cloudflarestorage.com/tapped-media/users/u1/avatar/x.jpg?X-Amz-Signature=s",
     "method":"PUT","headers":{"content-type":"image/jpeg","content-length":"4","x-amz-content-sha256":"abc"},
     "url":"https://media.tapped.ai/users/u1/avatar/x.jpg","expiresAt":"2026-10-15T00:10:00Z"}
    """

    @Test func requestsTicketThenPutsBytesToR2() async throws {
        let session = StubUploadURLProtocol.session(responses: [
            "/app/v1/uploads": (200, Self.ticket),
            "/tapped-media/users/u1/avatar/x.jpg": (200, ""),
        ])
        let repository = TappedAPIStorageRepository(baseURL: URL(string: "https://api.tapped.ai")!, session: session, idToken: { "token" })
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])

        let url = try await repository.uploadProfilePicture(userId: "u1", imageData: jpeg)

        #expect(url.absoluteString == "https://media.tapped.ai/users/u1/avatar/x.jpg")
        let requests = StubUploadURLProtocol.requests
        #expect(requests.map(\.path) == ["/app/v1/uploads", "/tapped-media/users/u1/avatar/x.jpg"])
        let ticketRequest = try #require(requests.first)
        #expect(ticketRequest.authorization == "Bearer token")
        let sent = try JSONSerialization.jsonObject(with: ticketRequest.body) as? [String: Any]
        #expect(sent?["kind"] as? String == "avatar")
        #expect(sent?["contentType"] as? String == "image/jpeg")
        #expect(sent?["size"] as? Int == 4)
        #expect((sent?["sha256"] as? String)?.count == 64)
        #expect(requests.last?.method == "PUT")
        #expect(requests.last?.contentType == "image/jpeg")
    }

    @Test func failedPutThrows() async {
        let session = StubUploadURLProtocol.session(responses: [
            "/app/v1/uploads": (200, Self.ticket),
            "/tapped-media/users/u1/avatar/x.jpg": (403, "<Error/>"),
        ])
        let repository = TappedAPIStorageRepository(baseURL: URL(string: "https://api.tapped.ai")!, session: session, idToken: { "token" })
        await #expect(throws: StorageUploadError.uploadFailed(statusCode: 403)) {
            try await repository.uploadOpportunityFlier(opportunityId: "o1", jpegData: Data([0xFF, 0xD8, 0xFF]))
        }
    }

    @Test func sniffsContentType() {
        #expect(UploadRequest.contentType(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D])) == "image/png")
        #expect(UploadRequest.contentType(of: Data([0xFF, 0xD8, 0xFF])) == "image/jpeg")
    }
}

/// Serves canned responses by path and records each request, including streamed upload bodies.
final class StubUploadURLProtocol: URLProtocol {
    struct Recorded: Sendable {
        let path: String
        let method: String?
        let authorization: String?
        let contentType: String?
        let body: Data
    }

    struct State {
        var responses: [String: (status: Int, body: String)] = [:]
        var requests: [Recorded] = []
    }

    static let state = Mutex(State())

    static func session(responses: [String: (status: Int, body: String)]) -> URLSession {
        state.withLock { $0 = State(responses: responses) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubUploadURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var requests: [Recorded] { state.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable, case let n = stream.read(&buffer, maxLength: buffer.count), n > 0 {
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let recorded = Recorded(
            path: url.path(),
            method: request.httpMethod,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: body
        )
        let response = Self.state.withLock { state in
            state.requests.append(recorded)
            return state.responses[url.path()] ?? (404, "{}")
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
