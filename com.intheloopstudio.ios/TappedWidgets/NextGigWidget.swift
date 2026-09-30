import SwiftUI
import TappedDomain
import WidgetKit

struct NextGigEntry: TimelineEntry {
    var date: Date
    var content: NextGigTimeline.Content
}

/// Reads the snapshot the app writes to the `group.com.intheloopstudio` container.
struct NextGigProvider: TimelineProvider {
    var store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> NextGigEntry {
        NextGigEntry(date: .now, content: .nearby(count: 4))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextGigEntry) -> Void) {
        let now = Date.now
        completion(NextGigEntry(date: now, content: NextGigTimeline.content(store.load(), at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextGigEntry>) -> Void) {
        completion(Self.timeline(store.load(), now: .now))
    }

    static func timeline(_ snapshot: WidgetSnapshot, now: Date) -> Timeline<NextGigEntry> {
        let entries = NextGigTimeline.entries(snapshot, now: now).map { NextGigEntry(date: $0.date, content: $0.content) }
        return Timeline(entries: entries, policy: .after(NextGigTimeline.reloadDate(snapshot, now: now)))
    }
}

struct NextGigWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextGig", provider: NextGigProvider()) { entry in
            NextGigView(entry: entry)
        }
        .configurationDisplayName("Next Gig")
        .description("Your next confirmed booking, or new gigs near you.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextGigView: View {
    let entry: NextGigEntry
    @Environment(\.widgetFamily) private var family

    private var format: GigFormat { GigFormat() }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                LinearGradient(colors: [WidgetStyle.accent, WidgetStyle.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(url)
    }

    private var url: URL? {
        switch entry.content {
        case let .gig(gig): gig.bookingURL
        case .nearby: URL(string: "com.intheloopstudio://gigs")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (family, entry.content) {
        case let (.accessoryInline, .gig(gig)):
            Text(format.nextGig(gig, now: entry.date))
        case let (.accessoryInline, .nearby(count)):
            Label(GigFormat.nearbyGigs(count), systemImage: "music.mic")
        case let (.accessoryCircular, .gig(gig)):
            circular(top: format.day(gig.startTime, now: entry.date), bottom: format.time(gig.startTime))
        case let (.accessoryCircular, .nearby(count)):
            circular(top: count.map(String.init) ?? "–", bottom: "gigs")
        case let (.accessoryRectangular, .gig(gig)):
            VStack(alignment: .leading, spacing: 0) {
                Text("next gig").font(.caption2.weight(.semibold)).widgetAccentable()
                Text(gig.venueName).font(.headline).lineLimit(1)
                Text("\(format.day(gig.startTime, now: entry.date)) · \(format.time(gig.startTime))").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let (.accessoryRectangular, .nearby(count)):
            VStack(alignment: .leading, spacing: 0) {
                Text("tapped").font(.caption2.weight(.semibold)).widgetAccentable()
                Text(GigFormat.nearbyGigs(count)).font(.headline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let (_, .gig(gig)):
            small(
                eyebrow: "next gig",
                title: gig.venueName,
                detail: "\(format.day(gig.startTime, now: entry.date)) · \(format.time(gig.startTime))"
            )
        case let (_, .nearby(count)):
            small(eyebrow: "tapped", title: GigFormat.nearbyGigs(count), detail: "tap to see gigs")
        }
    }

    private func circular(top: String, bottom: String) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(top).font(.headline).minimumScaleFactor(0.6)
                Text(bottom).font(.caption2).minimumScaleFactor(0.6)
            }
            .padding(4)
        }
    }

    private func small(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image("TappedLogo").resizable().scaledToFit().frame(height: 16)
                Spacer()
                Image(systemName: "music.mic").font(.caption)
            }
            Spacer(minLength: 0)
            Text(eyebrow).font(.caption.weight(.semibold)).opacity(0.85)
            Text(title).font(.headline).lineLimit(3).minimumScaleFactor(0.7)
            Text(detail).font(.caption).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemSmall) {
    NextGigWidget()
} timeline: {
    NextGigEntry(date: .now, content: .gig(GigNight(bookingId: "b", venueName: "The Camel", startTime: .now.addingTimeInterval(86_400 * 2), endTime: .now.addingTimeInterval(86_400 * 2 + 7_200))))
    NextGigEntry(date: .now, content: .nearby(count: 4))
}
