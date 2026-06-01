@testable import App
import XCTest
import SportsCalModel

/// Pins the F1 persist-guards: a failed source returns empty, and we must never
/// overwrite last-known-good Redis data with that empty result.
final class F1EnrichmentWriteGuardTests: XCTestCase {
    func test_emptyCircuits_notPersisted() {
        XCTAssertFalse(F1EnrichmentJob.shouldPersistCircuits([:]))
    }

    func test_nonEmptyCircuits_persisted() {
        let circuit = F1CircuitInfo(circuitName: "Circuit de Monaco", locality: "Monte Carlo", country: "Monaco")
        XCTAssertTrue(F1EnrichmentJob.shouldPersistCircuits(["Monaco Grand Prix": circuit]))
    }

    func test_emptyStandings_notPersisted() {
        XCTAssertFalse(F1EnrichmentJob.shouldPersistStandings(F1Standings()))
    }

    func test_standingsWithDrivers_persisted() {
        let standings = F1Standings(
            driverStandings: [F1DriverStanding(position: 1, driverName: "Verstappen", constructorName: "Red Bull", points: 100, wins: 5)],
            constructorStandings: []
        )
        XCTAssertTrue(F1EnrichmentJob.shouldPersistStandings(standings))
    }

    func test_standingsWithConstructorsOnly_persisted() {
        let standings = F1Standings(
            driverStandings: [],
            constructorStandings: [F1ConstructorStanding(position: 1, constructorName: "Red Bull", points: 200, wins: 8)]
        )
        XCTAssertTrue(F1EnrichmentJob.shouldPersistStandings(standings))
    }
}
