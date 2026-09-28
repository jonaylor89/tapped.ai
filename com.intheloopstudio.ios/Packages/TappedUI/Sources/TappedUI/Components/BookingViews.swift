import MapKit
import SwiftUI
import TappedDomain

public extension BookingStatus {
    var systemImage: String {
        switch self {
        case .pending: "clock.fill"
        case .confirmed: "checkmark.seal.fill"
        case .canceled: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: TappedColors.warning
        case .confirmed: TappedColors.success
        case .canceled: TappedColors.error
        }
    }
}

/// Status capsule (`GlassPill` with the status icon + tint in `booking_view.dart`).
public struct BookingStatusBadge: View {
    let status: BookingStatus

    public init(_ status: BookingStatus) {
        self.status = status
    }

    public var body: some View {
        Label(status.formattedName, systemImage: status.systemImage)
            .font(TappedTypography.label)
            .foregroundStyle(status.tint)
            .padding(.horizontal, TappedSpacing.sm)
            .padding(.vertical, TappedSpacing.xs)
            .background(status.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(status.tint.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel("status: \(status.formattedName)")
    }
}

/// Glass booking summary (`booking_container.dart` / `booking_tile.dart`): date tile, name,
/// counterpart and time, status badge.
public struct BookingCard: View {
    let booking: Booking
    let counterpart: UserModel?
    let showsStatus: Bool

    public init(booking: Booking, counterpart: UserModel?, showsStatus: Bool = true) {
        self.booking = booking
        self.counterpart = counterpart
        self.showsStatus = showsStatus
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.md) {
            BookingDateTile(date: booking.startTime, tint: booking.isCanceled ? .secondary : TappedColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.name?.isEmpty == false ? booking.name! : "booking")
                    .font(TappedTypography.headingXs)
                    .lineLimit(1)
                    .strikethrough(booking.isCanceled, color: .secondary)
                if let counterpart {
                    HStack(spacing: TappedSpacing.xs) {
                        UserAvatar(user: counterpart, size: 18)
                        Text(counterpart.displayName)
                            .lineLimit(1)
                    }
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
                } else if booking.addedByUser {
                    Label("added by you", systemImage: "plus.circle")
                        .font(TappedTypography.bodySm)
                        .foregroundStyle(.secondary)
                }
                Text(Self.timeRange(booking))
                    .font(TappedTypography.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if showsStatus {
                BookingStatusBadge(booking.status)
            }
        }
        .padding(TappedSpacing.md)
        .contentShape(RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous), interactive: true)
        .accessibilityElement(children: .combine)
    }

    public static func timeRange(_ booking: Booking) -> String {
        let start = booking.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let end = booking.endTime.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)".lowercased()
    }
}

/// Calendar-style month/day tile.
public struct BookingDateTile: View {
    let date: Date
    let tint: Color

    public init(date: Date, tint: Color = TappedColors.accent) {
        self.date = date
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).lowercased())
                .font(TappedTypography.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(date.formatted(.dateTime.day()))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 48, height: 52)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: TappedRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TappedRadius.md, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// Static MapKit snapshot with a centred pin. Re-renders on size / colour-scheme changes.
public struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    let spanMeters: CLLocationDistance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: UIImage?

    public init(location: Location, spanMeters: CLLocationDistance = 1200) {
        coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
        self.spanMeters = spanMeters
    }

    private struct Key: Hashable {
        var width: CGFloat
        var height: CGFloat
        var dark: Bool
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white, TappedColors.error)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: Key(width: proxy.size.width, height: proxy.size.height, dark: colorScheme == .dark)) {
                snapshot = await render(size: proxy.size)
            }
        }
        .accessibilityLabel("map")
    }

    private func render(size: CGSize) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: spanMeters, longitudinalMeters: spanMeters)
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            traits.displayScale = displayScale
        }
        return try? await MKMapSnapshotter(options: options).start().image
    }
}

/// Success hero for confirmation screens (`booking_confirmation_view.dart`).
public struct ConfirmationHero: View {
    let title: String
    let message: String?
    let systemImage: String
    let tint: Color

    public init(_ title: String, message: String? = nil, systemImage: String = "checkmark", tint: Color = TappedColors.success) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: TappedSpacing.xl) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 120, height: 120)
                .tappedGlass(.regular, in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                .tappedShadow()
                .accessibilityHidden(true)
            VStack(spacing: TappedSpacing.sm) {
                Text(title)
                    .font(TappedTypography.headingLg)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(TappedTypography.bodyMd)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("BookingStatusBadge") {
    HStack {
        ForEach(BookingStatus.allCases, id: \.self) { BookingStatusBadge($0) }
    }
    .padding()
}

#Preview("BookingCard") {
    VStack(spacing: TappedSpacing.md) {
        BookingCard(booking: Samples.bookings[0], counterpart: Samples.venues[0])
        BookingCard(booking: Samples.bookings[1], counterpart: Samples.venues[3])
        BookingCard(booking: Samples.bookings[6], counterpart: nil)
        BookingCard(booking: Samples.bookings[7], counterpart: Samples.venues[9])
    }
    .padding()
    .background(PreviewBackdrop())
}

#Preview("BookingCard dark") {
    VStack(spacing: TappedSpacing.md) {
        BookingCard(booking: Samples.bookings[0], counterpart: Samples.venues[0])
        BookingCard(booking: Samples.bookings[1], counterpart: Samples.venues[3])
    }
    .padding()
    .background(PreviewBackdrop())
    .preferredColorScheme(.dark)
}

#Preview("MapSnapshotView") {
    MapSnapshotView(location: Samples.venues[0].location ?? .rva)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
        .padding()
}

#Preview("ConfirmationHero") {
    ConfirmationHero("booking requested", message: "your booking will be confirmed once the performer accepts.")
        .padding()
        .background(PreviewBackdrop())
}
