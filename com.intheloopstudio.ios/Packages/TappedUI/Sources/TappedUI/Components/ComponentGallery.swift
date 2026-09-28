import SwiftUI
import TappedDomain

/// Every shared component in one scrollable view. Used by the smoke test and as a design review preview.
public struct ComponentGallery: View {
    @State private var segment = "venues"
    @State private var text = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TappedSpacing.xl) {
                GlassSearchField(action: {}) {
                    GlassIconButton("person.crop.circle", accessibilityLabel: "profile") {}
                }
                GlassSearchField(text: $text, placeholder: "search a city")
                GlassSegmentedPicker(selection: $segment, options: ["venues", "gigs"]) { $0 }
                GlassBanner("finish setting up", message: "add a photo and genres", action: {}, onDismiss: {})
                HStack {
                    GlassCapsuleButton("filters", systemImage: "line.3.horizontal.decrease") {}
                    GlassIconButton("location", accessibilityLabel: "locate") {}
                    GlassChip("rock", count: 3, isSelected: true)
                }
                GlassEmptyState("no venues here", message: "try zooming out")
                UserTile(user: Samples.venues[0])
                HStack {
                    UserCard(user: Samples.performer)
                    UserCard(user: Samples.performers[1], isLocked: true)
                }
                OpportunityCard(opportunity: Samples.opportunities[0], venueName: "the camel")
                HStack {
                    RatingStars(4.5)
                    QRCodeView("https://app.tapped.ai/u/djnova").frame(width: 96, height: 96)
                }
                ErrorView(retry: {})
                WaitlistView(isOnWaitlist: false) {}
            }
            .padding(GlassMetrics.edgeInset)
        }
        .background(PreviewBackdrop())
    }
}

#Preview("ComponentGallery") { ComponentGallery() }
#Preview("ComponentGallery dark") { ComponentGallery().preferredColorScheme(.dark) }
