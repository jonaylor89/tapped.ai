import CryptoKit
import FirebaseAuth
import Foundation

/// Live `StorageRepository`: the Tapped API presigns an upload (`POST /app/v1/uploads`) and the bytes go
/// straight to R2. The returned `https://media.tapped.ai/…` URL is content-addressed, so it never changes.
public struct TappedAPIStorageRepository: StorageRepository {
    public typealias IDTokenProvider = @Sendable () async throws -> String?

    private let client: TappedAPIDataClient
    private let session: URLSession

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        idToken: @escaping IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }
    ) {
        self.client = TappedAPIDataClient(baseURL: baseURL, session: session, idToken: idToken)
        self.session = session
    }

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        try await upload(imageData, request: UploadRequest(kind: "avatar", data: imageData))
    }

    public func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL {
        try await upload(jpegData, request: UploadRequest(kind: "opportunityFlier", data: jpegData, opportunityId: opportunityId))
    }

    private func upload(_ data: Data, request: UploadRequest) async throws -> URL {
        guard let body = try await client.request(["uploads"], method: "POST", body: JSONEncoder().encode(request)) else {
            throw StorageUploadError.ticketUnavailable
        }
        let ticket = try JSONDecoder().decode(UploadTicket.self, from: body)
        var put = URLRequest(url: ticket.uploadUrl)
        put.httpMethod = ticket.method
        for (name, value) in ticket.headers { put.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await session.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StorageUploadError.uploadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return ticket.url
    }
}

struct UploadRequest: Encodable, Equatable {
    let kind: String
    let contentType: String
    let sha256: String
    let size: Int
    var opportunityId: String?

    init(kind: String, data: Data, opportunityId: String? = nil) {
        self.kind = kind
        self.contentType = Self.contentType(of: data)
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.size = data.count
        self.opportunityId = opportunityId
    }

    /// Callers pass compressed JPEGs, but picked images can arrive as PNG or HEIC.
    static func contentType(of data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.count >= 12, head[0..<4] == [0x52, 0x49, 0x46, 0x46], head[8..<12] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if head.count >= 12, head[4..<8] == [0x66, 0x74, 0x79, 0x70] { return "image/heic" }
        return "image/jpeg"
    }
}

struct UploadTicket: Decodable {
    let uploadUrl: URL
    let method: String
    let headers: [String: String]
    let url: URL
}

public enum StorageUploadError: LocalizedError, Sendable, Equatable {
    case ticketUnavailable
    case uploadFailed(statusCode: Int?)

    public var errorDescription: String? {
        switch self {
        case .ticketUnavailable, .uploadFailed: "error uploading the image"
        }
    }
}
