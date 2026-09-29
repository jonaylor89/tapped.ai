import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/booking/booking_view.dart` (payment UI intentionally removed).
struct BookingDetailView: View {
    @State private var model: BookingDetailViewModel
    @State private var confirmingCancel = false
    @State private var confirmingDeny = false
    @State private var showsReview = false
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    init(dependencies: Dependencies, booking: Booking, currentUser: UserModel, now: @escaping () -> Date = { .now }) {
        _model = State(initialValue: BookingDetailViewModel(dependencies: dependencies, booking: booking, currentUser: currentUser, now: now))
    }

    private var booking: Booking { model.booking }

    var body: some View {
        List {
            Section { header }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            Section("parties") {
                partyRow(model.requester, role: "booker", fallback: booking.addedByUser ? "added by you" : "unknown booker")
                partyRow(model.requestee, role: "performer", fallback: "performer")
            }

            Section("when") {
                LabeledContent("date", value: booking.startTime.formatted(.dateTime.weekday(.wide).month(.wide).day().year()).lowercased())
                LabeledContent("time", value: timeRange)
                LabeledContent("length", value: Duration.seconds(booking.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            }

            if let location = booking.location {
                Section("where") {
                    MapSnapshotView(location: location)
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets())
                    Button {
                        if let url = mapsURL(location) { openURL(url) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.place?.name ?? "location").foregroundStyle(.primary)
                                if let address = model.place?.shortFormattedAddress {
                                    Text(address).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square").foregroundStyle(TappedColors.accent)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("opens in maps")
                }
            }

            if let service = model.service {
                Section("service") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.title)
                        if !service.description.isEmpty {
                            Text(service.description).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !booking.note.isEmpty {
                Section("note") { Text(booking.note) }
            }

            if model.canReview {
                Section {
                    Button { showsReview = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("how was the gig?").foregroundStyle(.primary)
                                Text("leave a review for \(model.reviewee?.displayName ?? "them")")
                                    .font(TappedTypography.bodySm).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "star.bubble").foregroundStyle(TappedColors.warning)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } else if model.hasReviewed {
                Section {
                    Label("review posted", systemImage: "checkmark.bubble").foregroundStyle(.secondary)
                }
            }

            if model.canCancel {
                Section {
                    Button("cancel booking", role: .destructive) { confirmingCancel = true }
                } footer: {
                    Text("need to change something? contact support@tapped.ai")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TappedColors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if model.canRespond { respondBar }
        }
        .disabled(model.isUpdating)
        .overlay { if model.isUpdating { ProgressView().controlSize(.large) } }
        .navigationTitle("booking")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("cancel this booking?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("cancel booking", role: .destructive) { Task { await model.cancel() } }
            Button("keep booking", role: .cancel) {}
        } message: {
            Text("the other party will be notified.")
        }
        .confirmationDialog("deny this request?", isPresented: $confirmingDeny, titleVisibility: .visible) {
            Button("deny", role: .destructive) { Task { await model.deny() } }
            Button("not now", role: .cancel) {}
        }
        .alert("booking", isPresented: errorBinding) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showsReview) {
            BookingReviewSheet(model: model)
        }
        .task { await model.load() }
        .sensoryFeedback(.success, trigger: model.booking.status) { old, new in old != .confirmed && new == .confirmed }
        .gigNight(model, showsReview: $showsReview)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.sm) {
            BookingStatusBadge(booking.status)
            Text(booking.name?.isEmpty == false ? booking.name! : "booking")
                .font(TappedTypography.headingLg)
            Text(model.statusMessage)
                .font(TappedTypography.bodyMd)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TappedSpacing.xs)
        .padding(.bottom, TappedSpacing.xs)
    }

    private var respondBar: some View {
        HStack(spacing: TappedSpacing.md) {
            Button(role: .destructive) { confirmingDeny = true } label: {
                Label("deny", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass)
            Button { Task { await model.confirm() } } label: {
                Label("accept", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
        }
        .font(TappedTypography.headingXs)
        .controlSize(.large)
        .disabled(model.isUpdating)
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.bottom, TappedSpacing.sm)
    }

    @ViewBuilder
    private func partyRow(_ user: UserModel?, role: String, fallback: String) -> some View {
        if let user {
            Button {
                router.push(.profile(userId: user.id, user: user))
            } label: {
                UserTile(user: user, subtitle: user.id == model.currentUser.id ? "\(role) · you" : role) {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            LabeledContent(role, value: fallback)
        }
    }

    private var timeRange: String {
        "\(booking.startTime.formatted(date: .omitted, time: .shortened)) – \(booking.endTime.formatted(date: .omitted, time: .shortened))".lowercased()
    }

    private func mapsURL(_ location: Location) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(location.lat),\(location.lng)"),
            URLQueryItem(name: "q", value: model.place?.name ?? booking.name ?? "booking"),
        ]
        return components?.url
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Star rating + text review for the other party once a confirmed gig has ended.
struct BookingReviewSheet: View {
    @Bindable var model: BookingDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StarRatingPicker(rating: $model.reviewRating)
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("rate \(model.reviewee?.displayName ?? "them")")
                }
                Section("review") {
                    TextField("what stood out?", text: $model.reviewText, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("leave a review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSubmittingReview {
                        ProgressView()
                    } else {
                        Button("post", systemImage: "checkmark") {
                            Task { if await model.submitReview() { dismiss() } }
                        }
                        .disabled(model.reviewRating == 0)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("pending, as performer") {
    BookingDetailView(dependencies: .mock(signedIn: true), booking: Samples.bookings[1], currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview()
}

#Preview("upcoming dark") {
    BookingDetailView(dependencies: .mock(signedIn: true), booking: Samples.bookings[0], currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview(dark: true)
}

#Preview("past, review prompt") {
    BookingDetailView(dependencies: .mock(signedIn: true), booking: Samples.bookings[3], currentUser: Samples.performer, now: { Samples.referenceDate })
        .bookingsPreview()
}
