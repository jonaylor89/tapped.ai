import Foundation
import Testing
@testable import TappedDomain

@Suite("UserModel decoding")
struct UserModelDecodingTests {
    @Test func decodesVenueWithDefaultsAndNormalisation() throws {
        let venue = try Fixture.decode(UserModel.self, "user_venue")
        #expect(venue.id == "venue-1")
        #expect(venue.username == Username("thecameo"))
        #expect(venue.occupations == ["Venue"], "scalar occupations from Typesense are normalised to a list")
        #expect(venue.timestamp == Date(timeIntervalSince1970: 1_719_878_400.5))
        #expect(venue.location == .rva)
        #expect(venue.venueInfo?.capacity == 250)
        #expect(venue.venueInfo?.type == .bar)
        #expect(venue.venueInfo?.responseRate == 0.82)
        #expect(venue.isVenue)
        #expect(!venue.isPerformer)
        #expect(venue.socialFollowing.audienceSize == 12_300)
        #expect(venue.emailNotifications.appReleases == false)
        #expect(venue.emailNotifications.directMessages == true)
        #expect(venue.pushNotifications == .empty)
        #expect(venue.phoneNumber == nil)
        #expect(venue.displayName == "The Camel")
    }

    @Test func decodesPerformerWithFlutterDefaults() throws {
        let performer = try Fixture.decode(UserModel.self, "user_performer")
        #expect(performer.timestamp == Date(timeIntervalSince1970: 1_719_878_400))
        #expect(performer.displayName == "djnova", "empty artistName falls back to username")
        let info = try #require(performer.performerInfo)
        #expect(info.category == .hometownHero)
        #expect(info.rating == 5, "missing rating defaults to Option.of(5)")
        #expect(info.label == "Independent", "null label defaults to Independent")
        #expect(info.reviewCount == 3)
        #expect(info.averageTicketPrice == 2500)
        #expect(performer.bookerInfo?.rating == 4.5)
        #expect(performer.stripeConnectedAccountId == "acct_123")
        #expect(performer.email.isEmpty)
    }

    @Test func minimalDocumentDecodes() throws {
        let data = Data(#"{"id":"x","username":"Y"}"#.utf8)
        let user = try TappedCoding.jsonDecoder().decode(UserModel.self, from: data)
        #expect(user == UserModel(id: "x", username: "y"))
    }

    @Test func roundTripsThroughEncoder() throws {
        let venue = try Fixture.decode(UserModel.self, "user_venue")
        let encoded = try TappedCoding.jsonEncoder().encode(venue)
        let decoded = try TappedCoding.jsonDecoder().decode(UserModel.self, from: encoded)
        #expect(decoded == venue)
    }

    @Test func usernameEncodesAsBareString() throws {
        let json = try JSONEncoder().encode(["username": Username("  MiXeD ")])
        #expect(String(decoding: json, as: UTF8.self) == #"{"username":"mixed"}"#)
    }
}
