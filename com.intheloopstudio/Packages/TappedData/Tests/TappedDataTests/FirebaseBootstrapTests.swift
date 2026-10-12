import Foundation
import Testing
@testable import TappedData

@Suite("Firebase emulator config")
struct FirebaseBootstrapTests {
    @Test func parsesHostAndPort() {
        let address = FirebaseBootstrap.emulatorAddress("HOST", environment: ["HOST": "localhost:9099"])
        #expect(address?.host == "localhost")
        #expect(address?.port == 9099)
    }

    @Test func rejectsMissingOrMalformedAddresses() {
        #expect(FirebaseBootstrap.emulatorAddress("HOST", environment: [:]) == nil)
        #expect(FirebaseBootstrap.emulatorAddress("HOST", environment: ["HOST": "localhost"]) == nil)
        #expect(FirebaseBootstrap.emulatorAddress("HOST", environment: ["HOST": ":9099"]) == nil)
    }

    @Test func localAppIsADemoProject() {
        #expect(FirebaseBootstrap.localProjectID.hasPrefix("demo-"))
        #expect(FirebaseBootstrap.localOptions.projectID == FirebaseBootstrap.localProjectID)
    }

    @Test func persistedDefaultsFillMissingLaunchEnvironment() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set("localhost:9099", forKey: "FIREBASE_AUTH_EMULATOR_HOST")
        defaults.set("http://localhost:9999", forKey: "TAPPED_API_URL")
        defaults.set("ignored", forKey: "UNRELATED")
        let merged = LaunchEnvironment.merged(["TAPPED_API_URL": "http://localhost:8080"], defaults: defaults)
        #expect(merged["FIREBASE_AUTH_EMULATOR_HOST"] == "localhost:9099")
        #expect(merged["TAPPED_API_URL"] == "http://localhost:8080")
        #expect(merged["UNRELATED"] == nil)
    }
}
