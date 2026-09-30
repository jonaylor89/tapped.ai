import AppIntents
import Foundation
import TappedDomain

/// Siri / Spotlight / Action button entry points.
struct TappedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindPaidGigsIntent(),
            phrases: [
                "Find paid gigs near me this weekend in \(.applicationName)",
                "Find paid gigs this weekend with \(.applicationName)",
                "\(.applicationName) paid gigs this weekend",
            ],
            shortTitle: "Paid Gigs This Weekend",
            systemImageName: "music.mic"
        )
        AppShortcut(
            intent: ShareProfileIntent(),
            phrases: [
                "Share my \(.applicationName) profile",
                "Show my \(.applicationName) QR code",
                "Show my \(.applicationName) code",
            ],
            shortTitle: "Share My Profile",
            systemImageName: "qrcode"
        )
    }
}

/// Opens the gigs near the performer, narrowed to paid ones this weekend.
struct FindPaidGigsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Paid Gigs This Weekend"
    static let description = IntentDescription("Shows paid gigs near you this weekend in Tapped.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    static let url = URL(string: "com.intheloopstudio://gigs?paid=1&when=weekend")!

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.inbound.open(Self.url)
        return .result()
    }
}

/// Opens Share Profile straight into the full-screen QR code for in-person scanning.
struct ShareProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Share My Tapped Profile"
    static let description = IntentDescription("Shows your Tapped profile QR code so someone can scan it.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    static let url = URL(string: "com.intheloopstudio://share_profile?qr=1")!

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.inbound.open(Self.url)
        return .result()
    }
}
