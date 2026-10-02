import SwiftUI
import TappedDomain

/// Circular profile image with initials fallback (`user_avatar.dart`).
public struct UserAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat
    let isVerified: Bool

    public init(url: URL?, name: String, size: CGFloat = 44, isVerified: Bool = false) {
        self.url = url
        self.name = name
        self.size = size
        self.isVerified = isVerified
    }

    public init(user: UserModel, size: CGFloat = 44, isVerified: Bool = false) {
        self.init(url: user.profilePicture.flatMap(URL.init(string:)), name: user.displayName, size: size, isVerified: isVerified)
    }

    public var body: some View {
        RemoteImage(url: url) { initials }
            .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(.white, TappedColors.accent)
                    .accessibilityLabel("verified")
            }
        }
        .accessibilityLabel(name)
    }

    private var initials: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().lowercased()
        return ZStack {
            Circle().fill(TappedColors.accent.opacity(0.15))
            Text(letters.isEmpty ? "?" : letters)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(TappedColors.accent)
        }
    }
}

/// List row for a user (search results, venue hits).
public struct UserTile<Trailing: View>: View {
    let user: UserModel
    let subtitle: String?
    let trailing: Trailing

    public init(user: UserModel, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.user = user
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.md) {
            UserAvatar(user: user)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(TappedTypography.headingXs)
                    .lineLimit(1)
                Text(subtitle ?? "@\(user.username.username)")
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, TappedSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Vertical card for horizontally scrolling carousels (top performers).
public struct UserCard: View {
    let user: UserModel
    let isLocked: Bool

    public init(user: UserModel, isLocked: Bool = false) {
        self.user = user
        self.isLocked = isLocked
    }

    public var body: some View {
        VStack(spacing: TappedSpacing.sm) {
            UserAvatar(user: user, size: 72)
                .blur(radius: isLocked ? 6 : 0)
            VStack(spacing: 2) {
                Text(isLocked ? "premium" : user.displayName)
                    .font(TappedTypography.label)
                    .lineLimit(1)
                if let category = user.performerInfo?.category, !isLocked {
                    Text(category.formattedName.lowercased())
                        .font(TappedTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 104)
        .padding(.vertical, TappedSpacing.md)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).padding(TappedSpacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("UserAvatar") {
    HStack(spacing: TappedSpacing.lg) {
        UserAvatar(user: Samples.performer, size: 64, isVerified: true)
        UserAvatar(user: Samples.venues[0], size: 44)
        UserAvatar(url: nil, name: "", size: 32)
    }
    .padding()
}

#Preview("UserTile") {
    List {
        UserTile(user: Samples.venues[0], subtitle: "bar · 250 cap") {
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        UserTile(user: Samples.performer)
    }
}

#Preview("UserCard") {
    HStack {
        UserCard(user: Samples.performer)
        UserCard(user: Samples.performers[1], isLocked: true)
    }
    .padding()
}
