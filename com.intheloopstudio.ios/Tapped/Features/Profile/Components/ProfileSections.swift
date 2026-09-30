import PhotosUI
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Arrangement: Equatable {
        case row, grid, list
    }

    /// Four columns normally, 2×2 from xxLarge, labelled rows at accessibility sizes.
    static func arrangement(for size: DynamicTypeSize) -> Arrangement {
        if size.isAccessibilitySize { return .list }
        return size >= .xxLarge ? .grid : .row
    }

    var body: some View {
        Group {
            switch Self.arrangement(for: dynamicTypeSize) {
            case .row:
                HStack(spacing: 0) {
                    ForEach(stats) { cell($0).frame(maxWidth: .infinity) }
                }
                .padding(.vertical, TappedSpacing.md)
            case .grid:
                Grid(horizontalSpacing: 0, verticalSpacing: TappedSpacing.md) {
                    ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(stats[start..<min(start + 2, stats.count)]) { cell($0).frame(maxWidth: .infinity) }
                        }
                    }
                }
                .padding(.vertical, TappedSpacing.md)
            case .list:
                VStack(spacing: 0) {
                    ForEach(stats) { stat in
                        LabeledContent {
                            Text(stat.value).font(.headline).monospacedDigit().foregroundStyle(.primary).fixedSize()
                        } label: {
                            Text(stat.label).lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .padding(.vertical, TappedSpacing.sm)
                        if stat.id != stats.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, TappedSpacing.lg)
                .padding(.vertical, TappedSpacing.xs)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
    }

    private func cell(_ stat: Stat) -> some View {
        VStack(spacing: 2) {
            Text(stat.value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
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
                BookingCard(booking: Samples.bookings[0], counterpart: Samples.venues[0]).padding(.horizontal)
            }
            ProfileSection(title: "reviews") {
                ReviewCard(review: .performer(Samples.performerReviews[0]), reviewer: Samples.venues[0]).padding(.horizontal)
            }
        }
    }
}


/// Inline "add a photo" prompt shown on your own profile until a photo is set.
struct ProfilePhotoPrompt: View {
    let isUploading: Bool
    let onPick: (Data) async -> Void
    @State private var item: PhotosPickerItem?

    static let title = "add a photo"
    static let message = "profiles with a photo get more bookings"

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            HStack(spacing: TappedSpacing.md) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(TappedColors.accentText)
                    .frame(width: 44, height: 44)
                    .background(TappedColors.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title).font(TappedTypography.headingXs).foregroundStyle(.primary)
                    Text(Self.message).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isUploading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .profileCard()
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .accessibilityLabel("\(Self.title) — \(Self.message)")
        .onChange(of: item) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await onPick(data) }
                self.item = nil
            }
        }
    }
}

/// Setup-checklist progress ring (same tasks as `TasksView`).
struct ProfileCompletenessRing: View {
    let progress: Double
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(TappedColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .padding(6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("profile \(Int((progress * 100).rounded())) percent complete")
    }
}

#Preview("setup") {
    VStack(spacing: TappedSpacing.lg) {
        ProfilePhotoPrompt(isUploading: false) { _ in }
        ProfileCompletenessRing(progress: 0.6)
    }
    .padding()
}
