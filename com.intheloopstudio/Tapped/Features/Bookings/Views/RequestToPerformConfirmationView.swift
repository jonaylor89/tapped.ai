import SwiftUI
import TappedDomain
import TappedUI

/// Port of `lib/ui/request_to_perform/request_to_perform_confirmation_view.dart`.
struct RequestToPerformConfirmationView: View {
    let venues: [UserModel]
    @Environment(Router.self) private var router

    private var message: String { Self.message(for: venues) }

    /// Where replies land: Messages in the app and the performer's email.
    static func message(for venues: [UserModel]) -> String {
        let names = venues.map(\.displayName)
        let who = switch names.count {
        case 0: "the venue"
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]) and \(names.count - 1) others"
        }
        return "when \(who) \(names.count > 1 ? "reply" : "replies"), you'll see it in Messages and get an email."
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            confirmation
            ScrollView { confirmation }
        }
    }

    private var confirmation: some View {
        VStack(spacing: TappedSpacing.xl) {
            Spacer()
            ConfirmationHero("pitch sent", message: message, systemImage: "paperplane.fill")
            if !venues.isEmpty {
                VStack(spacing: 0) {
                    ForEach(venues) { venue in
                        UserTile(user: venue, subtitle: venue.venueInfo?.bookingEmail) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(TappedColors.success)
                        }
                        .padding(.horizontal, TappedSpacing.md)
                        .padding(.vertical, TappedSpacing.sm)
                    }
                }
                .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
            }
            NotificationsPromptCard(context: .requestToPerform, venueName: venues.count == 1 ? venues.first?.displayName : nil)
            Spacer()
            GlassSubmitButton("Done") {
                while let last = router.path.last, last.isRequestToPerformFlowStep { router.pop() }
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("request sent") {
    RequestToPerformConfirmationView(venues: Array(Samples.venues.prefix(2))).bookingsPreview()
}

#Preview("request sent dark") {
    RequestToPerformConfirmationView(venues: Array(Samples.venues.prefix(2))).bookingsPreview(dark: true)
}
