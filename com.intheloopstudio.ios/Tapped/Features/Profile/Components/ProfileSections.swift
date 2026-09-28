import SwiftUI
import TappedDomain
import TappedUI

/// Titled profile section with an optional trailing action (`see all`, `add`).
struct ProfileSection<Content: View>: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, TappedSpacing.lg)
            content
        }
    }
}

/// Rounded card background used by every profile section.
struct ProfileCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(TappedSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
    }
}

extension View {
    func profileCard() -> some View { modifier(ProfileCardBackground()) }
}

/// Audience / bookings / rating / reviews counters under the hero.
struct ProfileStats: View {
    struct Stat: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stats) { stat in
                VStack(spacing: 2) {
                    Text(stat.value)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(stat.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, TappedSpacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
    }
}

/// Collapsible bio text.
struct ProfileBio: View {
    let bio: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
            Text(bio)
                .font(.body)
                .lineLimit(isExpanded ? nil : 4)
            if bio.count > 180 {
                Button(isExpanded ? "less" : "more") { withAnimation(.snappy) { isExpanded.toggle() } }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .profileCard()
    }
}

struct ProfileInfoList: View {
    let rows: [ProfileInfoRow]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if let url = row.url {
                    Button { openURL(url) } label: { rowContent(row) }
                        .buttonStyle(.plain)
                } else {
                    rowContent(row)
                }
                if row.id != rows.last?.id { Divider().padding(.leading, 36) }
            }
        }
        .profileCard()
    }

    private func rowContent(_ row: ProfileInfoRow) -> some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: row.systemImage)
                .foregroundStyle(TappedColors.accent)
                .frame(width: 24)
            Text(row.title)
                .foregroundStyle(.secondary)
            Spacer(minLength: TappedSpacing.md)
            Text(row.value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(row.url == nil ? Color.primary : TappedColors.accent)
                .lineLimit(2)
        }
        .font(.subheadline)
        .padding(.vertical, TappedSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

struct ProfileSocialsRow: View {
    let socials: [ProfileSocial]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TappedSpacing.sm) {
                ForEach(socials) { social in
                    Button {
                        if let url = social.url { openURL(url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            SwiftUI.Label(social.name, systemImage: social.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TappedColors.accent)
                            Text(social.followers > 0 ? "\(ProfileViewModel.compact(social.followers)) followers" : "@\(social.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, TappedSpacing.md)
                        .padding(.vertical, TappedSpacing.sm)
                        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: TappedRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TappedSpacing.lg)
        }
    }
}

struct ServiceRow: View {
    let service: Service

    var body: some View {
        HStack(alignment: .top, spacing: TappedSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title.lowercased())
                    .font(.headline)
                if !service.description.isEmpty {
                    Text(service.description.lowercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProfileViewModel.currency(service.rate))
                    .font(.headline)
                    .monospacedDigit()
                Text(service.rateType == .hourly ? "per hour" : "flat rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BookingCard: View {
    let booking: Booking
    let counterpart: String

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(TappedColors.accent)
                Text(booking.startTime.formatted(.dateTime.month(.abbreviated).day().year()).lowercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if booking.startTime > .now {
                    Text("upcoming")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TappedColors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(TappedColors.accent, lineWidth: 1))
                }
            }
            Text(counterpart.lowercased())
                .font(.headline)
                .lineLimit(1)
            Text((booking.name ?? "booking").lowercased())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
        .profileCard()
    }
}

struct ReviewCard: View {
    let review: Review
    let reviewer: UserModel?

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.sm) {
            HStack(spacing: TappedSpacing.sm) {
                if let reviewer { UserAvatar(user: reviewer, size: 32) }
                VStack(alignment: .leading, spacing: 0) {
                    Text((reviewer?.displayName ?? "anonymous").lowercased())
                        .font(.subheadline.weight(.semibold))
                    Text(review.fields.timestamp.formatted(.relative(presentation: .named)).lowercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RatingStars(Double(review.fields.overallRating))
            }
            Text(review.fields.overallReview.lowercased())
                .font(.subheadline)
        }
        .profileCard()
    }
}

#Preview("sections") {
    ScrollView {
        VStack(alignment: .leading, spacing: TappedSpacing.xl) {
            ProfileStats(stats: [.init(value: "22.5k", label: "followers"), .init(value: "31", label: "bookings"), .init(value: "4.8", label: "rating")])
                .padding(.horizontal)
            ProfileSection(title: "services", actionTitle: "add", action: {}) {
                VStack { ForEach(Samples.services.prefix(2)) { ServiceRow(service: $0).profileCard() } }
                    .padding(.horizontal)
            }
            ProfileSection(title: "bookings") {
                BookingCard(booking: Samples.bookings[0], counterpart: "the camel").padding(.horizontal)
            }
            ProfileSection(title: "reviews") {
                ReviewCard(review: .performer(Samples.performerReviews[0]), reviewer: Samples.venues[0]).padding(.horizontal)
            }
        }
    }
}
