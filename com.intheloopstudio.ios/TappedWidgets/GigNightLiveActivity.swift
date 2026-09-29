import ActivityKit
import AppIntents
import SwiftUI
import TappedDomain
import WidgetKit

struct GigNightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GigNightAttributes.self) { context in
            GigNightLockScreenView(gig: context.attributes.gig, phase: phase(context))
                .activityBackgroundTint(WidgetStyle.deep.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.gig.bookingURL)
        } dynamicIsland: { context in
            let gig = context.attributes.gig
            let phase = phase(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(gig.venueName).font(.headline).lineLimit(1)
                    } icon: {
                        Image(systemName: "music.mic").foregroundStyle(WidgetStyle.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if phase == .upcoming {
                        GigCountdown(gig: gig, phase: phase).font(.headline).foregroundStyle(WidgetStyle.accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GigNightDetail(gig: gig, phase: phase, compact: true)
                }
            } compactLeading: {
                Image(systemName: phase == .review ? "star.fill" : "music.mic").foregroundStyle(WidgetStyle.accent)
            } compactTrailing: {
                GigCountdown(gig: gig, phase: phase).foregroundStyle(WidgetStyle.accent)
            } minimal: {
                GigCountdown(gig: gig, phase: phase, minimal: true).foregroundStyle(WidgetStyle.accent)
            }
            .widgetURL(gig.bookingURL)
            .keylineTint(WidgetStyle.accent)
        }
    }

    private func phase(_ context: ActivityViewContext<GigNightAttributes>) -> GigNightPhase {
        context.state.displayPhase(for: context.attributes.gig, isStale: context.isStale)
    }
}

/// Counts down to the set time; during the set shows the time left, after it a star.
struct GigCountdown: View {
    let gig: GigNight
    let phase: GigNightPhase
    var minimal = false

    var body: some View {
        switch phase {
        case .upcoming:
            Text(timerInterval: Date.now...max(gig.startTime, .now), countsDown: true, showsHours: !minimal)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: minimal ? 40 : 64)
                .accessibilityLabel("starts in \(GigFormat.countdown(from: .now, to: gig.startTime))")
        case .onStage:
            Text(timerInterval: Date.now...max(gig.endTime, .now), countsDown: true, showsHours: !minimal)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: minimal ? 40 : 64)
                .accessibilityLabel("on stage, \(GigFormat.countdown(from: .now, to: gig.endTime)) left")
        case .review, .over:
            Image(systemName: "star.fill").accessibilityLabel(GigFormat.reviewPrompt(gig.venueName))
        }
    }
}

struct GigNightLockScreenView: View {
    let gig: GigNight
    let phase: GigNightPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image("TappedLogo").resizable().scaledToFit().frame(height: 14)
                Spacer()
                Text(phase == .upcoming ? "gig night" : phase == .onStage ? "on stage" : "wrapped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(phase == .review || phase == .over ? GigFormat.reviewPrompt(gig.venueName) : gig.venueName)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Spacer()
                if phase == .upcoming || phase == .onStage {
                    GigCountdown(gig: gig, phase: phase).font(.title3.weight(.semibold)).foregroundStyle(WidgetStyle.accent)
                }
            }
            GigNightDetail(gig: gig, phase: phase, compact: false)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// Set time + Directions before/during the set; the 5-star review prompt after it.
struct GigNightDetail: View {
    let gig: GigNight
    let phase: GigNightPhase
    let compact: Bool

    private var format: GigFormat { GigFormat() }

    var body: some View {
        switch phase {
        case .upcoming, .onStage:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase == .upcoming ? "set time" : "on until \(format.time(gig.endTime))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(format.setTime(start: gig.startTime, end: gig.endTime))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if gig.directionsURL != nil {
                    Button(intent: OpenVenueDirectionsIntent(gig: gig)) {
                        Label("Directions", systemImage: "car.fill").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WidgetStyle.accent)
                }
            }
        case .review, .over:
            VStack(alignment: .leading, spacing: 6) {
                if compact {
                    Text(GigFormat.reviewPrompt(gig.venueName)).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                HStack(spacing: compact ? 10 : 14) {
                    ForEach(1...5, id: \.self) { rating in
                        Button(intent: RateGigIntent(bookingId: gig.bookingId, rating: rating)) {
                            Image(systemName: "star.fill")
                                .font(compact ? .title3 : .title2)
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(rating) star\(rating == 1 ? "" : "s")")
                    }
                }
            }
        }
    }
}

#Preview("Lock Screen", as: .content, using: GigNightAttributes(gig: GigNight(
    bookingId: "b", venueName: "The Camel", latitude: 37.55, longitude: -77.45,
    startTime: .now.addingTimeInterval(8_040), endTime: .now.addingTimeInterval(15_240)
))) {
    GigNightLiveActivity()
} contentStates: {
    GigNightAttributes.ContentState(phase: .upcoming)
    GigNightAttributes.ContentState(phase: .review)
}
