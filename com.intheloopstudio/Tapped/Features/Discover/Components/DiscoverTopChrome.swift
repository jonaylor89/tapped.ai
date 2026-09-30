import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `_TopChrome`: avatar · search capsule · messages, then venues/gigs, banner, "search this area".
struct DiscoverTopChrome: View {
    @Bindable var model: DiscoverViewModel
    let unreadMessages: Int
    var unreadActivities = 0
    let push: (Route) -> Void

    var body: some View {
        VStack(spacing: TappedSpacing.md) {
            HStack(spacing: TappedSpacing.sm) {
                Button {
                    push(.profile(userId: model.currentUser.id, user: model.currentUser))
                } label: {
                    UserAvatar(user: model.currentUser, size: GlassMetrics.control - 6)
                        .padding(3)
                        .tappedGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(GlassPressStyle())
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(count: unreadActivities).offset(x: 4, y: -4)
                }
                .accessibilityLabel("profile")

                GlassSearchField(action: { push(.search) })

                GlassIconButton("bubble.left.and.bubble.right.fill", accessibilityLabel: "messages") {
                    push(.messagingChannelList)
                }
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(count: unreadMessages).offset(x: 4, y: -4)
                }
            }

            GlassSegmentedPicker(
                selection: Binding(get: { model.overlay }, set: { overlay in Task { await model.select(overlay) } }),
                options: MapOverlay.allCases,
                title: \.rawValue
            )
            .frame(width: 220)

            if let message = model.tasksBannerMessage {
                GlassBanner(
                    "finish setting up",
                    message: message,
                    systemImage: "checkmark.circle",
                    action: { push(.tasks) },
                    onDismiss: { withAnimation(GlassMotion.ease) { model.isTasksBannerDismissed = true } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.resultsExpired {
                GlassCapsuleButton("search this area", systemImage: "arrow.clockwise", style: .accent) {
                    Task { await model.searchThisArea() }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.top, TappedSpacing.sm)
        .animation(GlassMotion.ease, value: model.resultsExpired)
    }
}
