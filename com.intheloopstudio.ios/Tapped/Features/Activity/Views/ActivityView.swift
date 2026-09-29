import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/activity/activity_view.dart`.
struct ActivityView: View {
    @Environment(Router.self) private var router
    @State private var model: ActivityViewModel

    init(dependencies: Dependencies, currentUser: UserModel) {
        _model = State(initialValue: ActivityViewModel(dependencies: dependencies, currentUser: currentUser))
    }

    var body: some View {
        content
            .navigationTitle("activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("mark all read", systemImage: "checkmark.circle") {
                        Task { await model.markAllRead() }
                    }
                    .disabled(!model.hasUnread)
                }
            }
            .task { if model.activities.isEmpty { await model.refresh() } }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            LoadingView()
        } else if let message = model.errorMessage, model.activities.isEmpty {
            ErrorView(message) { Task { await model.refresh() } }
        } else if model.activities.isEmpty {
            ScrollView {
                GlassEmptyState("no activity yet", message: "follows and booking updates will show up here", systemImage: "bell.slash")
                    .padding(.top, TappedSpacing.xxxl * 3)
            }
            .refreshable { await model.refresh() }
        } else {
            List {
                ForEach(model.activities) { activity in
                    Button {
                        Task {
                            if let route = await model.open(activity) { router.push(route) }
                        }
                    } label: {
                        ActivityRow(activity: activity, fromUser: model.fromUser(for: activity))
                    }
                    .tint(.primary)
                    .swipeActions(edge: .leading) {
                        if !activity.common.markedRead {
                            Button("mark read", systemImage: "checkmark") { Task { await model.markRead(activity) } }
                                .tint(TappedColors.accent)
                        }
                    }
                    .onAppear {
                        if activity.id == model.activities.last?.id { Task { await model.loadMore() } }
                    }
                }
                if model.isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }
}

/// Dart `ActivityTile`: avatar, bold name, message, relative time, unread dot.
struct ActivityRow: View {
    let activity: Activity
    let fromUser: UserModel?

    private var isUnread: Bool { !activity.common.markedRead }

    var body: some View {
        HStack(alignment: .center, spacing: TappedSpacing.md) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .foregroundStyle(isUnread ? .primary : .secondary)
                    .lineLimit(2)
                Text(activity.common.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(TappedColors.accent)
                .frame(width: 10, height: 10)
                .opacity(isUnread ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, TappedSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? "unread" : "")
    }

    @ViewBuilder private var leading: some View {
        if let fromUser {
            UserAvatar(user: fromUser, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: activity.systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(TappedColors.accent, in: Circle())
                        .offset(x: 4, y: 4)
                }
        } else {
            Image(systemName: activity.systemImage)
                .font(.title3)
                .foregroundStyle(TappedColors.accent)
                .frame(width: 44, height: 44)
                .background(TappedColors.accent.opacity(0.12), in: Circle())
        }
    }

    private var title: Text {
        if case .searchAppearance = activity {
            return Text("people are finding you in search · \(activity.message)")
        }
        let name = (fromUser?.displayName ?? "someone").lowercased()
        return Text("\(Text(name).fontWeight(.bold)) \(activity.message)")
    }
}

#Preview("activity") {
    NavigationStack {
        ActivityView(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
    }
    .environment(Router())
}

#Preview("empty") {
    NavigationStack {
        ActivityView(dependencies: .mock(signedIn: true), currentUser: Samples.venues[0])
    }
    .environment(Router())
}
