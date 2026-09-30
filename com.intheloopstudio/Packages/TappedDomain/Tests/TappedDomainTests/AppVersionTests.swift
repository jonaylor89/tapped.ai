import Testing
@testable import TappedDomain

@Suite("AppVersion")
struct AppVersionTests {
    @Test func comparesNumerically() throws {
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.9")))
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("2.0.0+45")) < #require(AppVersion("2.0.1+1")))
    }

    @Test func parsesBuildAndRejectsGarbage() {
        #expect(AppVersion("3.4.5+99")?.build == "99")
        #expect(AppVersion("3.4.5+99")?.firestoreValue == "3.4.5+99")
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v1.2") == nil)
        #expect(AppVersion("1..2") == nil)
    }
}
