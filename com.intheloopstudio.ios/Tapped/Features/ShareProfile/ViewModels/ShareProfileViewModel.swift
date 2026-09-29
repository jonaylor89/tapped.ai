import Foundation
import Observation
import SwiftUI
import TappedData
import TappedDomain
import TappedUI
import UIKit

@Observable
@MainActor
final class ShareProfileViewModel {
    let userId: String
    private(set) var user: UserModel?
    private(set) var errorMessage: String?
    private(set) var avatar: UIImage?
    /// The designed card rendered with `ImageRenderer`, shared alongside the profile URL.
    private(set) var cardImage: Image?
    private(set) var qrCode: CGImage?
    var toast: String?
    var showsFullScreenQR = false

    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository
    private let loadImage: @Sendable (URL) async -> UIImage?

    init(
        dependencies: Dependencies,
        userId: String,
        user: UserModel?,
        loadImage: @escaping @Sendable (URL) async -> UIImage? = ShareProfileViewModel.download
    ) {
        self.userId = userId
        self.user = user
        database = dependencies.database
        analytics = dependencies.analytics
        self.loadImage = loadImage
    }

    func load() async {
        if user == nil {
            errorMessage = nil
            do {
                user = try await database.getUserById(userId)
                if user == nil { errorMessage = "this profile doesn't exist" }
            } catch {
                errorMessage = "couldn't load profile"
            }
        }
        guard let user else { return }
        qrCode = ShareProfileCardRenderer.qrCode(for: user.profileURL)
        cardImage = ShareProfileCardRenderer.render(user: user, avatar: nil, qrCode: qrCode)
        if avatar == nil, let url = user.profilePicture.flatMap(URL.init(string:)) {
            avatar = await loadImage(url)
            if avatar != nil { cardImage = ShareProfileCardRenderer.render(user: user, avatar: avatar, qrCode: qrCode) }
        }
        if ShareProfileQRRequest.take() { showsFullScreenQR = true }
    }

    func copyLink() {
        guard let user else { return }
        UIPasteboard.general.url = user.profileURL
        toast = "link copied"
        Task { await analytics.track("copy_profile_link") }
    }

    func showQR() {
        showsFullScreenQR = true
        Task { await analytics.track("show_profile_qr") }
    }

    nonisolated static func download(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// Set by the "Share my Tapped profile" shortcut so Share Profile opens straight into the full-screen QR.
@MainActor
enum ShareProfileQRRequest {
    static var isPending = false

    static func take() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

@MainActor
enum ShareProfileCardRenderer {
    static let cardWidth: CGFloat = 340

    /// `CIQRCodeGenerator` output for the public profile URL, on a transparent background.
    static func qrCode(for url: URL) -> CGImage? {
        QRCode.image(for: url.absoluteString, scale: 12)
    }

    static func render(user: UserModel, avatar: UIImage?, qrCode: CGImage?, scale: CGFloat = 3) -> Image? {
        let renderer = ImageRenderer(content: ShareProfileCard(user: user, avatar: avatar, qrCode: qrCode).frame(width: cardWidth))
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
