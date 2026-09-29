import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Inline "turn on notifications" card for confirmation screens. Renders nothing when it shouldn't ask.
struct NotificationsPromptCard: View {
    let context: NotificationsPromptModel.Context
    var venueName: String?
    var venueId: String?

    var body: some View {
        NotificationsPromptCardContent(context: context, venueName: venueName, venueId: venueId)
    }
}

private struct NotificationsPromptCardContent: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellViewModel.self) private var shell: ShellViewModel?
    @State private var model: NotificationsPromptModel?
    let context: NotificationsPromptModel.Context
    let venueName: String?
    let venueId: String?

    var body: some View {
        VStack(spacing: 0) {
            if let model, model.isVisible {
                card(model).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(GlassMotion.ease, value: model?.isVisible)
        .task {
            let model = NotificationsPromptModel(
                context: context,
                dependencies: dependencies,
                userId: session?.currentUser?.id ?? shell?.currentUser.id,
                venueName: venueName,
                venueId: venueId
            )
            self.model = model
            await model.load()
        }
    }

    private func card(_ model: NotificationsPromptModel) -> some View {
        VStack(alignment: .leading, spacing: TappedSpacing.md) {
            Label {
                Text(model.message)
                    .font(TappedTypography.bodySm)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bell.badge.fill").foregroundStyle(TappedColors.accent)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TappedSpacing.sm) { buttons(model) }
                VStack(alignment: .leading, spacing: TappedSpacing.sm) { buttons(model) }
            }
        }
        .padding(TappedSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
    }

    @ViewBuilder private func buttons(_ model: NotificationsPromptModel) -> some View {
        Button("turn on notifications") { Task { await model.turnOn() } }
            .buttonStyle(.glassProminent)
        Button("not now") { model.notNow() }
            .buttonStyle(.glass)
    }
}

#Preview {
    NotificationsPromptCard(context: .requestToPerform, venueName: Samples.venues[0].displayName)
        .padding()
        .environment(\.dependencies, .mock(signedIn: true))
}
