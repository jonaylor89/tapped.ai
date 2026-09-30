import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `user_reviews_feed.dart`, plus a native write-review sheet.
struct UserReviewsView: View {
    @State private var model: UserReviewsViewModel
    @State private var isWriting: Bool
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUser: UserModel, userId: String, isWriting: Bool = false) {
        _model = State(initialValue: UserReviewsViewModel(dependencies: dependencies, currentUser: currentUser, userId: userId))
        _isWriting = State(initialValue: isWriting)
    }

    var body: some View {
        List {
            if let average = model.averageRating {
                Section {
                    HStack(spacing: TappedSpacing.lg) {
                        Text(average.formatted(.number.precision(.fractionLength(1))))
                            .font(TappedTypography.displayMd)
                        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                            RatingStars(average, size: 18)
                            Text("\(model.reviews.count) \(model.reviews.count == 1 ? "review" : "reviews")")
                                .font(TappedTypography.bodySm)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !model.reviews.isEmpty {
                Section {
                    ForEach(model.reviews) { review in
                        Button {
                            if let reviewer = model.reviewer(for: review) {
                                router.push(.profile(userId: reviewer.id, user: reviewer))
                            }
                        } label: {
                            ReviewCard(review: review, reviewer: model.reviewer(for: review))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: TappedSpacing.xs, leading: 0, bottom: TappedSpacing.xs, trailing: 0))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isLoading && model.reviews.isEmpty {
                LoadingView()
            } else if model.failed {
                ErrorView { Task { await model.load() } }
            } else if model.reviews.isEmpty {
                GlassEmptyState("no reviews yet", message: "reviews show up here after a booking", systemImage: "star.bubble")
            }
        }
        .navigationTitle(model.reviewee.map { "\($0.displayName.lowercased())'s reviews" } ?? "reviews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canWriteReview {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("write a review", systemImage: "square.and.pencil") { isWriting = true }
                }
            }
        }
        .sheet(isPresented: $isWriting) {
            WriteReviewSheet(revieweeName: model.reviewee?.displayName.lowercased() ?? "them") { rating, text in
                await model.submit(rating: rating, text: text)
            }
            .presentationDetents([.medium, .large])
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// Star picker + text in an inset-grouped form.
struct WriteReviewSheet: View {
    static let maxLength = 500

    let revieweeName: String
    let submit: (Int, String) async -> Bool

    @State private var rating = 0
    @State private var text = ""
    @State private var isSubmitting = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StarRatingPicker(rating: $rating)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("how was working with \(revieweeName)?")
                }
                Section {
                    TextField("share the details", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .onChange(of: text) { _, value in
                            if value.count > Self.maxLength { text = String(value.prefix(Self.maxLength)) }
                        }
                } footer: {
                    Text("\(text.count)/\(Self.maxLength) · reviews are public on their profile")
                }
            }
            .navigationTitle("write a review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("post", systemImage: "checkmark") {
                            Task {
                                isSubmitting = true
                                if await submit(rating, text) { dismiss() } else { failed = true }
                                isSubmitting = false
                            }
                        }
                        .disabled(rating == 0)
                    }
                }
            }
            .alert("couldn't post your review", isPresented: $failed) {
                Button("ok", role: .cancel) {}
            }
        }
    }
}

#Preview("reviews") {
    NavigationStack {
        UserReviewsView(dependencies: .mock(signedIn: true), currentUser: Samples.venues[0], userId: Samples.performer.id)
    }
    .environment(Router())
}

#Preview("empty") {
    NavigationStack {
        UserReviewsView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: Samples.venues[5].id)
    }
    .environment(Router())
}

#Preview("write") {
    Color.clear.sheet(isPresented: .constant(true)) {
        WriteReviewSheet(revieweeName: "dj nova") { _, _ in true }
            .presentationDetents([.medium, .large])
    }
}
