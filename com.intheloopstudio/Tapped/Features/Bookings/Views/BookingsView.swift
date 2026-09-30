import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/bookings/bookings_view.dart`: pending / upcoming / past glass booking cards.
struct BookingsView: View {
    @State private var model: BookingsViewModel
    let currentUser: UserModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, userId: String, currentUser: UserModel, now: @escaping () -> Date = { .now }) {
        _model = State(initialValue: BookingsViewModel(dependencies: dependencies, userId: userId, now: now))
        self.currentUser = currentUser
    }

    private var isOwn: Bool { model.userId == currentUser.id }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(spacing: TappedSpacing.md) {
                switch model.state {
                case .loading:
                    LoadingView().padding(.top, TappedSpacing.xxxl)
                case let .failed(message):
                    ErrorView(message) { Task { await model.load() } }
                case .loaded:
                    if model.visibleBookings.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.visibleBookings) { booking in
                            Button {
                                router.push(.booking(booking))
                            } label: {
                                BookingCard(booking: booking, counterpart: model.counterpart(for: booking))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset)
            .padding(.vertical, TappedSpacing.md)
            .animation(GlassMotion.ease, value: model.segment)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassSegmentedPicker(selection: $model.segment, options: BookingsViewModel.Segment.allCases) { $0.rawValue }
                .padding(.horizontal, GlassMetrics.edgeInset)
                .padding(.vertical, TappedSpacing.sm)
        }
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle("bookings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwn {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("booking history", systemImage: "map") { router.push(.bookingHistory(currentUser)) }
                    Button("add past booking", systemImage: "plus") { router.push(.addPastBooking) }
                }
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    private var emptyState: some View {
        let empty = model.emptyState
        return GlassEmptyState(empty.title, message: empty.message, systemImage: empty.systemImage) {
            if isOwn, model.segment == .past {
                Button("add past booking") { router.push(.addPastBooking) }
                    .buttonStyle(.glass)
            }
        }
        .padding(.top, TappedSpacing.xl)
    }
}

#Preview("bookings") {
    BookingsView(dependencies: .mock(signedIn: true), userId: Samples.performer.id, currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview()
}

#Preview("bookings dark") {
    BookingsView(dependencies: .mock(signedIn: true), userId: Samples.performer.id, currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview(dark: true)
}

#Preview("bookings empty") {
    BookingsView(dependencies: Dependencies.mock(signedIn: true), userId: "nobody", currentUser: Samples.performer)
        .bookingsPreview()
}
