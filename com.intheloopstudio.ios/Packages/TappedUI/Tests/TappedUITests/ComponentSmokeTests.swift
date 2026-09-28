import SwiftUI
import TappedDomain
import Testing
@testable import TappedUI

/// Renders every shared component offscreen in light and dark mode. Catches layout crashes and
/// zero-size regressions without a snapshot-diffing dependency.
@MainActor
@Suite("TappedUI smoke")
struct ComponentSmokeTests {
    static let components: [(String, AnyView)] = [
        ("GlassCapsuleButton", AnyView(GlassCapsuleButton("filters", systemImage: "line.3.horizontal.decrease") {})),
        ("GlassIconButton", AnyView(GlassIconButton("location", accessibilityLabel: "locate") {})),
        ("GlassChip", AnyView(GlassChip("rock", count: 2, isSelected: true))),
        ("GlassSegmentedPicker", AnyView(GlassSegmentedPicker(selection: .constant("venues"), options: ["venues", "gigs"]) { $0 }.frame(width: 240))),
        ("GlassSearchField", AnyView(GlassSearchField(action: {}).frame(width: 340))),
        ("GlassBanner", AnyView(GlassBanner("finish setting up", message: "add genres", action: {}).frame(width: 340))),
        ("GlassEmptyState", AnyView(GlassEmptyState("no venues here").frame(width: 340))),
        ("ErrorView", AnyView(ErrorView(retry: {}).frame(width: 340, height: 300))),
        ("MaintenanceView", AnyView(MaintenanceView().frame(width: 340, height: 400))),
        ("WaitlistView", AnyView(WaitlistView(isOnWaitlist: false) {}.frame(width: 340))),
        ("UserAvatar", AnyView(UserAvatar(user: Samples.performer, size: 64, isVerified: true))),
        ("UserTile", AnyView(UserTile(user: Samples.venues[0]).frame(width: 340))),
        ("UserCard", AnyView(UserCard(user: Samples.performer))),
        ("OpportunityCard", AnyView(OpportunityCard(opportunity: Samples.opportunities[0]))),
        ("RatingStars", AnyView(RatingStars(4.5))),
        ("GlassToast", AnyView(GlassToast("link copied"))),
        ("QRCodeView", AnyView(QRCodeView("https://app.tapped.ai/u/djnova").frame(width: 200, height: 200))),
        ("OpportunityFlier", AnyView(OpportunityFlier(opportunity: Samples.opportunities[0]).frame(width: 340, height: 200))),
        ("OpportunityTile", AnyView(OpportunityTile(opportunity: Samples.opportunities[0], venueName: "the camel").frame(width: 340))),
        ("SelectionIndicator", AnyView(SelectionIndicator(isSelected: true))),
        ("StarRatingPicker", AnyView(StarRatingPicker(rating: .constant(4)))),
        ("ReviewCard", AnyView(ReviewCard(review: .performer(Samples.performerReviews[0]), reviewer: Samples.venues[0]).frame(width: 340))),
        ("MultiSelectList", AnyView(NavigationStack { MultiSelectList("genres", items: ["rock", "jazz"], selection: .constant(["jazz"])) { $0 } }.frame(width: 390, height: 400))),
        ("ComponentGallery", AnyView(ComponentGallery().frame(width: 390, height: 844))),
    ]

    @Test(arguments: [ColorScheme.light, .dark])
    func rendersEveryComponent(scheme: ColorScheme) throws {
        for (name, view) in Self.components {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try #require(renderer.uiImage, "\(name) failed to render")
            #expect(image.size.width > 0 && image.size.height > 0, "\(name) rendered empty")
        }
    }

    @Test func sheetProgressMath() {
        typealias Sheet = MapsStyleSheet<EmptyView>
        #expect(Sheet.progress(sheetHeight: 100, containerHeight: 1000) == 0)
        #expect(Sheet.progress(sheetHeight: 1000, containerHeight: 1000) == 1)
        #expect(Sheet.morph(Sheet.mediumProgress) == 0)
        #expect(Sheet.morph(1) == 1)
        #expect(Sheet.chromeOpacity(0) == 1)
        #expect(Sheet.chromeOpacity(Sheet.mediumProgress) == 1)
        #expect(Sheet.chromeOpacity(1) == 0)
    }

    @Test func detentMapping() {
        for detent in MapsSheetDetent.allCases {
            #expect(MapsSheetDetent(detent.presentationDetent) == detent)
        }
    }

    @Test func qrCodeEncodesProfileLinks() throws {
        let image = try #require(QRCode.image(for: "https://app.tapped.ai/u/djnova", scale: 10))
        #expect(image.width == image.height)
        #expect(image.width >= 210)
    }

    @Test func tokensMatchFlutter() {
        #expect(TappedSpacing.lg == 16)
        #expect(TappedRadius.lg == 15)
        #expect(GlassRadius.sheet == 38)
        #expect(GlassMetrics.edgeInset == 16)
    }
}
