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
}
