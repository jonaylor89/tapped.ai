import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/profile/profile_view.dart` (own + other user).
struct ProfileView: View {
    @Environment(Router.self) private var router
    @Environment(ShellViewModel.self) private var shell: ShellViewModel?
    @State private var model: ProfileViewModel
    @State private var isShowingOptions = false
    @State private var isConfirmingBlock = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(dependencies: Dependencies, currentUser: UserModel, userId: String, user: UserModel? = nil) {
        _model = State(initialValue: ProfileViewModel(dependencies: dependencies, currentUser: currentUser, userId: userId, user: user))
    }

    var body: some View {
        content
            .navigationTitle(model.user?.displayName ?? "profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar { toolbar }
            .confirmationDialog("more options", isPresented: $isShowingOptions, titleVisibility: .hidden) { moreOptions }
            .confirmationDialog(
                "Block \(model.user?.displayName ?? "this user")?",
                isPresented: $isConfirmingBlock,
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) { Task { await model.block() } }
            } message: {
                Text("they won't be able to find your profile or message you")
            }
            .offlineBanner(isOffline: NetworkMonitor.shared.isOffline)
            .glassToast($model.toast)
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading where model.user == nil:
            LoadingView()
        case let .failed(message) where model.user == nil:
            ErrorView(message) { Task { await model.load() } }
        default:
            if let user = model.user {
                if model.isBlocked {
                    GlassEmptyState("you blocked this user", message: "unblock them to see their profile", systemImage: "hand.raised.fill") {
                        GlassCapsuleButton("unblock", style: .accent) { Task { await model.unblock() } }
                    }
                } else {
                    profile(user)
                }
            }
        }
    }

    private func profile(_ user: UserModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TappedSpacing.xl) {
                ProfileHero(user: user, subtitle: model.subtitle) { router.push(.image(url: $0)) }

                ProfileStats(stats: stats(for: user))
                    .padding(.horizontal, TappedSpacing.lg)
                    .padding(.top, -ProfileHero.statsOverlap)

                actionBar(user)
                    .padding(.horizontal, TappedSpacing.lg)

                if model.needsPhoto {
                    ProfilePhotoPrompt(isUploading: model.isUploadingPhoto) { await model.uploadPhoto($0) }
                        .padding(.horizontal, TappedSpacing.lg)
                }

                if !user.bio.isEmpty {
                    ProfileSection(title: "about") {
                        ProfileBio(bio: user.bio).padding(.horizontal, TappedSpacing.lg)
                    }
                }

                if !model.infoRows.isEmpty {
                    ProfileSection(title: "info") {
                        ProfileInfoList(rows: model.infoRows).padding(.horizontal, TappedSpacing.lg)
                    }
                }

                if model.showAudience, !model.socials.isEmpty || model.isCurrentUser {
                    ProfileSection(
                        title: "socials",
                        actionTitle: model.isCurrentUser ? "edit" : nil,
                        action: model.isCurrentUser ? { router.push(.settings) } : nil
                    ) {
                        if model.socials.isEmpty {
                            Text("add your socials so promoters can see your audience")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, TappedSpacing.lg)
                        } else {
                            ProfileSocialsRow(socials: model.socials)
                        }
                    }
                }

                servicesSection(user)
                bookingsSection(user)
                reviewsSection
            }
            .padding(.bottom, TappedSpacing.xxxl)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    private func stats(for user: UserModel) -> [ProfileStats.Stat] {
        var stats: [ProfileStats.Stat] = []
        if model.showAudience {
            stats.append(.init(value: ProfileViewModel.compact(user.socialFollowing.audienceSize), label: "followers"))
        }
        stats.append(.init(value: model.bookingCount.formatted(), label: "bookings"))
        if let rating = user.performerInfo?.rating ?? user.bookerInfo?.rating {
            stats.append(.init(value: rating.formatted(.number.precision(.fractionLength(1))), label: "rating"))
        }
        stats.append(.init(value: model.reviewCount.formatted(), label: "reviews"))
        return stats
    }

    // MARK: - action bar

    @ViewBuilder private func actionBar(_ user: UserModel) -> some View {
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TappedSpacing.sm))
            : AnyLayout(HStackLayout(spacing: TappedSpacing.sm))
        GlassEffectContainer(spacing: TappedSpacing.sm) {
            layout {
                if model.isCurrentUser {
                    GlassCapsuleButton("edit profile", systemImage: "pencil", style: .accent) { router.push(.settings) }
                    GlassCapsuleButton("share", systemImage: "square.and.arrow.up") {
                        router.push(.shareProfile(userId: user.id, user: user))
                    }
                    if model.setupProgress < 1 {
                        if !stacks { Spacer(minLength: 0) }
                        Button { router.push(.tasks) } label: {
                            HStack(spacing: TappedSpacing.sm) {
                                ProfileCompletenessRing(progress: model.setupProgress)
                                if stacks { Text("finish your profile").font(TappedTypography.label) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("opens your setup checklist")
                    }
                } else {
                    if model.canRequestToPerform {
                        GlassCapsuleButton("pitch", systemImage: "music.mic", style: .accent) {
                            router.push(.requestToPerform(venues: [user], collaborators: []))
                        }
                    }
                    if model.canRequestToBook {
                        GlassCapsuleButton("request to book", systemImage: "calendar.badge.plus", style: model.canRequestToPerform ? .regular : .accent) {
                            router.push(.serviceSelection(userId: user.id, requesteeStripeConnectedAccountId: nil))
                        }
                    }
                    if model.canMessage {
                        MessageUserButton(userId: user.id)
                    }
                }
            }
            .glassCapsuleFillsWidth(stacks)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - sections

    @ViewBuilder private func servicesSection(_ user: UserModel) -> some View {
        if !model.services.isEmpty || (model.isCurrentUser && user.isPerformer) {
            ProfileSection(
                title: "services",
                actionTitle: model.isCurrentUser ? "add" : nil,
                action: model.isCurrentUser ? { router.push(.createService(service: nil)) } : nil
            ) {
                VStack(spacing: TappedSpacing.sm) {
                    if model.services.isEmpty {
                        Text("add a service so venues know what you offer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.services) { service in
                        Button { router.push(.service(service, serviceUser: user)) } label: {
                            ServiceRow(service: service).profileCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TappedSpacing.lg)
            }
        }
    }

    @ViewBuilder private func bookingsSection(_ user: UserModel) -> some View {
        if !model.latestBookings.isEmpty || model.isCurrentUser {
            ProfileSection(title: "bookings", actionTitle: model.latestBookings.isEmpty ? (model.isCurrentUser ? "add past gig" : nil) : "see all") {
                if model.latestBookings.isEmpty { router.push(.addPastBooking) } else { router.push(.bookingHistory(user)) }
            } content: {
                if model.latestBookings.isEmpty {
                    Text("your past gigs are probably the most important part of your profile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TappedSpacing.lg)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TappedSpacing.sm) {
                            ForEach(model.latestBookings) { booking in
                                Button { router.push(.booking(booking)) } label: {
                                    BookingCard(booking: booking, counterpart: model.counterpart(for: booking), showsStatus: false)
                                        .frame(width: 280)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, TappedSpacing.lg)
                    }
                }
            }
        }
    }

    @ViewBuilder private var reviewsSection: some View {
        if let review = model.latestReview {
            ProfileSection(title: "reviews", actionTitle: "see all") {
                router.push(.reviews(userId: model.userId))
            } content: {
                ReviewCard(review: review, reviewer: model.latestReviewer)
                    .padding(.horizontal, TappedSpacing.lg)
            }
        }
    }

    // MARK: - toolbar + more options

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if model.isCurrentUser {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.activities) } label: {
                    Image(systemName: "bell.fill")
                        .overlay(alignment: .topTrailing) {
                            UnreadBadge(count: shell?.unreadActivities ?? 0).offset(x: 10, y: -10)
                        }
                }
                .accessibilityLabel("activity")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape.fill") }
                    .accessibilityLabel("settings")
            }
        } else if model.user != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingOptions = true } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("more options")
            }
        }
    }

    @ViewBuilder private var moreOptions: some View {
        if let user = model.user {
            Button("share profile") { router.push(.shareProfile(userId: user.id, user: user)) }
            Button("copy profile link") {
                UIPasteboard.general.url = user.profileURL
                model.toast = "link copied"
            }
            Button("report user", role: .destructive) { Task { await model.report() } }
            if model.isBlocked {
                Button("unblock user") { Task { await model.unblock() } }
            } else {
                Button("block user", role: .destructive) { isConfirmingBlock = true }
            }
        }
    }
}

#Preview("own profile") {
    NavigationStack {
        ProfileView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: Samples.performer.id)
    }
    .environment(Router())
    .environment(ShellViewModel(currentUser: Samples.performer))
}

#Preview("venue profile") {
    NavigationStack {
        ProfileView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: Samples.venues[0].id)
    }
    .environment(Router())
}
