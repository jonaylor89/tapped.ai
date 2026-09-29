import SwiftUI

/// Glass card wrapping `ContentUnavailableView` for empty results in floating contexts.
public struct GlassEmptyState<Actions: View>: View {
    let title: String
    let message: String?
    let systemImage: String
    let actions: Actions

    public init(_ title: String, message: String? = nil, systemImage: String = "magnifyingglass", @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            actions
        }
        .padding(TappedSpacing.lg)
        .frame(maxWidth: .infinity)
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
    }
}

/// Full-screen loading state: the animated Tapped logo (Rive) on the brand background.
public struct LoadingView: View {
    let message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: TappedSpacing.lg) {
            RiveView(.loadingLogo)
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)
            if let message {
                Text(message).font(TappedTypography.bodyMd).foregroundStyle(.secondary)
            } else {
                ProgressView().accessibilityLabel("loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TappedColors.background.ignoresSafeArea())
    }
}

/// Failure state: what failed, the likely cause and the next step (see `ErrorCopy`), plus a retry button.
public struct ErrorView: View {
    let message: String
    let systemImage: String
    let retry: (() -> Void)?

    public init(_ message: String = ErrorCopy.load("this"), systemImage: String = "wifi.exclamationmark", retry: (() -> Void)? = nil) {
        self.message = message
        self.systemImage = systemImage
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(ErrorCopy.headline(message), systemImage: systemImage)
        } description: {
            Text(ErrorCopy.detail(message))
        } actions: {
            if let retry {
                Button("try again", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.glass)
                    .tint(TappedColors.accent)
            }
        }
    }
}

/// Shown while Remote Config `down_for_maintenance` is true.
public struct MaintenanceView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView {
            Label("down for maintenance", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("we're making some improvements. check back soon.")
        }
        .background(TappedColors.background.ignoresSafeArea())
    }
}

/// Shown while this build is older than Remote Config's minimum version (replaces Flutter `upgrader`).
public struct UpdateRequiredView: View {
    let minimumVersion: String
    let update: () -> Void

    public init(minimumVersion: String, update: @escaping () -> Void) {
        self.minimumVersion = minimumVersion
        self.update = update
    }

    public var body: some View {
        ContentUnavailableView {
            Label("time to update", systemImage: "arrow.down.app")
        } description: {
            Text("this version of tapped is no longer supported. update to \(minimumVersion) or newer to keep going.")
        } actions: {
            Button(action: update) {
                Text("update tapped").frame(maxWidth: 240)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(TappedColors.accent)
        }
        .background(TappedColors.background.ignoresSafeArea())
    }
}

/// Premium waitlist prompt (`premium_waitlist_view.dart`).
public struct WaitlistView: View {
    let isOnWaitlist: Bool
    let join: () -> Void

    public init(isOnWaitlist: Bool, join: @escaping () -> Void) {
        self.isOnWaitlist = isOnWaitlist
        self.join = join
    }

    public var body: some View {
        VStack(spacing: TappedSpacing.xl) {
            Image(systemName: isOnWaitlist ? "checkmark.seal" : "crown")
                .font(.largeTitle.weight(.semibold))
                .imageScale(.large)
                .foregroundStyle(TappedColors.accent)
            VStack(spacing: TappedSpacing.sm) {
                Text(isOnWaitlist ? "you're on the list" : "tapped premium")
                    .font(TappedTypography.headingMd)
                Text(isOnWaitlist ? "we'll let you know as soon as premium opens up." : "get booked faster with premium insights. join the waitlist.")
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !isOnWaitlist {
                Button(action: join) {
                    Text("join waitlist").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(TappedColors.accent)
            }
        }
        .padding(TappedSpacing.xxl)
    }
}

#Preview("GlassEmptyState") {
    GlassEmptyState("no venues here", message: "try zooming out or changing filters") {
        GlassCapsuleButton("clear filters") {}
    }
    .padding()
    .background(PreviewBackdrop())
}

#Preview("LoadingView") { LoadingView() }
#Preview("ErrorView") { ErrorView(retry: {}) }
#Preview("MaintenanceView") { MaintenanceView() }
#Preview("UpdateRequiredView") { UpdateRequiredView(minimumVersion: "2.0.0") {} }
#Preview("UpdateRequiredView dark") { UpdateRequiredView(minimumVersion: "2.0.0") {}.preferredColorScheme(.dark) }
#Preview("WaitlistView") { WaitlistView(isOnWaitlist: false) {} }
#Preview("WaitlistView joined") { WaitlistView(isOnWaitlist: true) {} }
