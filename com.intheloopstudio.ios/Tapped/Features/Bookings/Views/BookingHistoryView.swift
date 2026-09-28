import MapKit
import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/booking_history/booking_history_view.dart`: past gigs as map annotations with a
/// floating glass card carousel.
struct BookingHistoryView: View {
    @State private var model: BookingHistoryViewModel
    @State private var position: MapCameraPosition = .automatic
    let currentUser: UserModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, user: UserModel, currentUser: UserModel, now: @escaping () -> Date = { .now }) {
        _model = State(initialValue: BookingHistoryViewModel(dependencies: dependencies, user: user, now: now))
        self.currentUser = currentUser
    }

    var body: some View {
        @Bindable var model = model
        Map(position: $position, selection: $model.selectedBookingId) {
            ForEach(model.mappedBookings) { booking in
                if let location = booking.location {
                    Marker(booking.name ?? "gig", systemImage: "music.mic", coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng))
                        .tint(booking.id == model.selectedBookingId ? TappedColors.accent : TappedColors.error)
                        .tag(booking.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top, spacing: 0) { summary }
        .safeAreaInset(edge: .bottom, spacing: 0) { carousel }
        .overlay {
            if !model.isLoading, model.bookings.isEmpty {
                GlassEmptyState("no past gigs yet", message: "confirmed bookings you've played show up on this map", systemImage: "map") {
                    if model.user.id == currentUser.id {
                        Button("add past booking") { router.push(.addPastBooking) }.buttonStyle(.glass)
                    }
                }
                .padding(GlassMetrics.edgeInset)
            }
        }
        .navigationTitle("booking history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.user.id == currentUser.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("add past booking", systemImage: "plus") { router.push(.addPastBooking) }
                }
            }
        }
        .onChange(of: model.selectedBookingId) { _, id in
            guard let location = model.bookings.first(where: { $0.id == id })?.location else { return }
            withAnimation(GlassMotion.spring) {
                position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng), latitudinalMeters: 3000, longitudinalMeters: 3000))
            }
        }
        .task { await model.load() }
    }

    private var summary: some View {
        HStack(spacing: TappedSpacing.sm) {
            UserAvatar(user: model.user, size: 28)
            Text(model.isLoading ? "loading…" : model.summary)
                .font(TappedTypography.label)
                .monospacedDigit()
        }
        .padding(.leading, TappedSpacing.xs)
        .padding(.trailing, TappedSpacing.md)
        .padding(.vertical, TappedSpacing.xs)
        .tappedGlass(in: Capsule())
        .tappedShadow()
        .padding(.top, TappedSpacing.sm)
    }

    @ViewBuilder
    private var carousel: some View {
        if !model.bookings.isEmpty {
            @Bindable var model = model
            ScrollView(.horizontal) {
                LazyHStack(spacing: TappedSpacing.md) {
                    ForEach(model.bookings) { booking in
                        Button {
                            if model.selectedBookingId == booking.id {
                                router.push(.booking(booking))
                            } else {
                                model.selectedBookingId = booking.id
                            }
                        } label: {
                            BookingCard(booking: booking, counterpart: model.requester(for: booking), showsStatus: false)
                                .overlay {
                                    if booking.id == model.selectedBookingId {
                                        RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous)
                                            .strokeBorder(TappedColors.accent, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal) { width, _ in width - GlassMetrics.edgeInset * 3 }
                        .id(booking.id)
                    }
                }
                .scrollTargetLayout()
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollPosition(id: $model.selectedBookingId, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, GlassMetrics.edgeInset, for: .scrollContent)
            .padding(.bottom, TappedSpacing.lg)
        }
    }
}

#Preview("booking history") {
    BookingHistoryView(dependencies: .mock(signedIn: true), user: Samples.performer, currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview()
}

#Preview("booking history dark") {
    BookingHistoryView(dependencies: .mock(signedIn: true), user: Samples.performer, currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview(dark: true)
}
