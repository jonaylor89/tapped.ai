import Foundation

/// `occupation.dart`. Occupations are free-form strings in Firestore (`users.occupations`),
/// so this wraps a raw string and exposes the curated list the Flutter app offers.
public struct Occupation: RawRepresentable, Codable, Sendable, Hashable, Identifiable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var id: String { rawValue }

    /// Discover filters venues with `occupations:=['Venue', 'venue']`.
    public static let venue: Occupation = "Venue"

    public static let all: [Occupation] = [
        "Performer", "Band", "DJ", "Music Producer", "Recording Engineer", "Audio Engineer", "Sound Designer",
        "Music Director", "A&R Coordinator", "Music Supervisor", "Tour Manager", "Booking Agent", "Concert Promoter",
        "Lawyer", "Public Relations Specialist", "Music Publicist", "Social Media Manager", "Music Journalist",
        "Music Critic", "Artist Manager", "Music Teacher", "Session Musician", "Composer", "Arranger", "Songwriter",
        "Music Therapist", "Music Librarian", "Music Licensing Coordinator", "Music Publisher", "Music Editor",
        "Music Video Director", "Radio DJ", "Performing Rights Organization", "Performing Rights Representative",
        "Music Attorney", "Radio Producer", "Radio Promotions Director", "Music Retail Store Manager",
        "Instrument Technician", "Road Crew Technician", "Sound Technician", "Live Sound Engineer",
        "Lighting Designer", "Stage Manager", "Merchandise Coordinator", "Talent Scout", "Record Label Executive",
        "Other",
    ]
}
