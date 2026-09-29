import SwiftUI
import TappedDomain
import Testing
@testable import TappedUI

@MainActor
@Suite("TappedUI booking components")
struct BookingComponentTests {
    static let components: [(String, AnyView)] = [
        ("BookingStatusBadge", AnyView(HStack { ForEach(BookingStatus.allCases, id: \.self) { BookingStatusBadge($0) } })),
        ("BookingCard", AnyView(BookingCard(booking: Samples.bookings[0], counterpart: Samples.venues[0]).frame(width: 360))),
        ("BookingCard added by user", AnyView(BookingCard(booking: Samples.bookings[6], counterpart: nil).frame(width: 360))),
        ("BookingDateTile", AnyView(BookingDateTile(date: Samples.referenceDate))),
        ("MapSnapshotView", AnyView(MapSnapshotView(location: .rva).frame(width: 340, height: 160))),
        ("ConfirmationHero", AnyView(ConfirmationHero("request sent", message: "we'll let you know").frame(width: 340))),
        ("StarRatingPicker", AnyView(StarRatingPicker(rating: .constant(3)))),
        ("GlassSubmitButton", AnyView(GlassSubmitButton("send", isSubmitting: true) {}.frame(width: 360))),
        ("ServiceRow", AnyView(ServiceRow(service: Samples.services[0]).frame(width: 360))),
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

    @Test func statusStyling() {
        #expect(BookingStatus.allCases.map(\.formattedName) == ["pending", "confirmed", "canceled"])
        #expect(Set(BookingStatus.allCases.map(\.systemImage)).count == BookingStatus.allCases.count)
    }

    @Test func timeRangeIsLowercase() {
        let text = BookingCard.timeRange(Samples.bookings[0])
        #expect(text == text.lowercased())
        #expect(text.contains("–"))
    }

    @Test func serviceRateFormatting() {
        #expect(Service(id: "a", userId: "u", rate: 15_000, rateType: .hourly).formattedRate == "$150 / hr")
        #expect(Service(id: "b", userId: "u", rate: 25_050, rateType: .fixed).formattedRate == "$250.50 flat")
    }
}
