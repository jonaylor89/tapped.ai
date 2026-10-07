import Foundation
import Testing
@testable import TappedData

@Suite("Remote Config")
struct RemoteConfigRepositoryTests {
    @Test func launchFetchIsBoundedWellUnderFirebasesDefault() {
        #expect(FirebaseRemoteConfigRepository.fetchTimeout <= 5)
    }

    @Test func mockServesTheCacheUntilTheFetchActivates() async throws {
        let remoteConfig = MockRemoteConfigRepository(
            minimumAppVersion: "1.0.0",
            fetched: .init(downForMaintenance: true, minimumAppVersion: "2.0.0")
        )
        #expect(await remoteConfig.activateCached())
        #expect(await !remoteConfig.getDownForMaintenanceStatus())
        #expect(await remoteConfig.getMinimumAppVersion() == "1.0.0")

        try await remoteConfig.fetchAndActivate()
        #expect(remoteConfig.fetchCount == 1)
        #expect(await remoteConfig.getDownForMaintenanceStatus())
        #expect(await remoteConfig.getMinimumAppVersion() == "2.0.0")
    }

    @Test func mockWithoutFetchedValuesKeepsTheCache() async throws {
        let remoteConfig = MockRemoteConfigRepository(downForMaintenance: true)
        try await remoteConfig.fetchAndActivate()
        #expect(await remoteConfig.getDownForMaintenanceStatus())
    }
}
