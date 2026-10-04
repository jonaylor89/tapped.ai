import Foundation

/// What the app shares with the "Next gig" widget through the App Group container.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// The performer's upcoming confirmed bookings, soonest first.
    public var upcomingGigs: [GigNight]
    /// Open gigs near the performer from the last Discover/opportunity search.
    public var nearbyGigCount: Int?
    public var updatedAt: Date

    public init(upcomingGigs: [GigNight] = [], nearbyGigCount: Int? = nil, updatedAt: Date = .now) {
        self.upcomingGigs = upcomingGigs
        self.nearbyGigCount = nearbyGigCount
        self.updatedAt = updatedAt
    }

    public static let empty = WidgetSnapshot(updatedAt: .distantPast)
}

/// `UserDefaults(suiteName: "group.com.intheloopstudio")` storage shared by the app and `TappedWidgets`.
public struct WidgetSnapshotStore: @unchecked Sendable {
    public static let appGroup = "group.com.intheloopstudio"
    static let key = "widget.snapshot"
    static let dismissedGigNightsKey = "gigNight.dismissed"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    public func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    public func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func update(_ change: (inout WidgetSnapshot) -> Void) {
        var snapshot = load()
        change(&snapshot)
        save(snapshot)
    }

    /// Bookings whose Gig Night activity was reviewed or dismissed, so it isn't restarted.
    public var dismissedGigNights: Set<String> {
        Set(defaults.stringArray(forKey: Self.dismissedGigNightsKey) ?? [])
    }

    public func dismissGigNight(_ bookingId: String) {
        defaults.set(Array(dismissedGigNights.union([bookingId])).sorted(), forKey: Self.dismissedGigNightsKey)
    }
}

/// Timeline for the "Next gig" widget: one entry now, then one each time the shown gig wraps.
public enum NextGigTimeline {
    public enum Content: Equatable, Sendable {
        case gig(GigNight)
        case nearby(count: Int?)
    }

    public struct Entry: Equatable, Sendable {
        public var date: Date
        public var content: Content
    }

    public static let maxEntries = 5
    public static let refreshInterval: TimeInterval = 60 * 60

    public static func content(_ snapshot: WidgetSnapshot, at date: Date) -> Content {
        if let gig = snapshot.upcomingGigs.sorted(by: { $0.startTime < $1.startTime }).first(where: { $0.endTime > date }) {
            return .gig(gig)
        }
        return .nearby(count: snapshot.nearbyGigCount)
    }

    public static func entries(_ snapshot: WidgetSnapshot, now: Date) -> [Entry] {
        let changes = snapshot.upcomingGigs.map(\.endTime).filter { $0 > now }.sorted()
        let dates = [now] + changes.prefix(maxEntries - 1)
        var entries: [Entry] = []
        for date in dates {
            let content = content(snapshot, at: date)
            if entries.last?.content != content { entries.append(Entry(date: date, content: content)) }
        }
        return entries
    }

    /// When WidgetKit should ask for a fresh timeline.
    public static func reloadDate(_ snapshot: WidgetSnapshot, now: Date) -> Date {
        let lastChange = snapshot.upcomingGigs.map(\.endTime).filter { $0 > now }.sorted().prefix(maxEntries - 1).last
        return max(lastChange ?? now, now).addingTimeInterval(lastChange == nil ? refreshInterval : 60)
    }
}
