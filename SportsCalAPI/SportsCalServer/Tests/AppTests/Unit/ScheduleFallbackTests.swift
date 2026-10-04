@testable import App
import XCTest
import SportsCalModel

/// The hourly schedule rebuild starts from an empty LiveScore. A league whose fetch
/// fails (or comes back empty) must keep its previous games instead of vanishing.
final class ScheduleFallbackTests: XCTestCase {

    private func game(_ id: String, league: Leagues, home: String = "H", away: String = "A") -> Game {
        TestGameFactory.make(idEvent: id, idLeague: String(league.rawValue), strHomeTeam: home, strAwayTeam: away)
    }

    func test_failedLeague_keepsExistingGames() {
        let existing = LiveScore(
            nba: LiveEvent(events: [game("n1", league: .nba)]),
            nhl: LiveEvent(events: [game("h1", league: .nhl), game("h2", league: .nhl)])
        )
        // NHL failed → rebuilt has no NHL bucket at all.
        let rebuilt = LiveScore(nba: LiveEvent(events: [game("n2", league: .nba)]))

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existing, leagues: [.nba, .nhl])

        XCTAssertEqual(result.schedule.nhl?.events.compactMap(\.idEvent), ["h1", "h2"])
        XCTAssertEqual(result.carried, [.nhl: 2])
        XCTAssertEqual(result.schedule.nba?.events.compactMap(\.idEvent), ["n2"],
                       "a league that fetched fine is the rebuild's, not the old schedule's")
    }

    func test_emptyLeagueInSharedBucket_carriedAlongsideOtherLeagues() {
        let existing = LiveScore(soccer: LiveEvent(events: [
            game("e1", league: .English_Premier_League),
            game("l1", league: .La_Liga),
        ]))
        // La Liga came back empty; EPL fetched.
        let rebuilt = LiveScore(soccer: LiveEvent(events: [game("e2", league: .English_Premier_League)]))

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(
            rebuilt: rebuilt, existing: existing, leagues: [.English_Premier_League, .La_Liga]
        )

        XCTAssertEqual(result.schedule.soccer?.events.compactMap(\.idEvent), ["e2", "l1"])
        XCTAssertEqual(result.carried, [.La_Liga: 1])
    }

    func test_leagueNotEligible_isNotCarried() {
        // WNBA's default board is a today window: empty is legitimate, so the caller
        // only lists it on a thrown fetch. Not listed here → yesterday's games drop.
        let existing = LiveScore(nba: LiveEvent(events: [game("w1", league: .wnba)]))
        let rebuilt = LiveScore(nba: LiveEvent(events: [game("n1", league: .nba)]))

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existing, leagues: [.nba])

        XCTAssertEqual(result.schedule.nba?.events.compactMap(\.idEvent), ["n1"])
        XCTAssertTrue(result.carried.isEmpty)
    }

    func test_ncaafCarriedIntoFootballBucket() {
        let existing = LiveScore(nfl: LiveEvent(events: [game("c1", league: .ncaaf), game("f1", league: .nfl)]))
        let rebuilt = LiveScore(nfl: LiveEvent(events: [game("f2", league: .nfl)]))

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existing, leagues: [.nfl, .ncaaf])

        XCTAssertEqual(result.schedule.nfl?.events.compactMap(\.idEvent), ["f2", "c1"])
    }

    func test_noExistingSchedule_returnsRebuiltUnchanged() {
        let rebuilt = LiveScore(nba: LiveEvent(events: [game("n1", league: .nba)]))
        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: nil, leagues: [.nhl])
        XCTAssertEqual(result.schedule, rebuilt)
        XCTAssertTrue(result.carried.isEmpty)
    }

    func test_carriedGamesAreNotDuplicated() {
        // Same event ID already present in the bucket (e.g. idLeague missing on rebuild).
        let orphan = TestGameFactory.make(idEvent: "h1", idLeague: nil, strHomeTeam: "H", strAwayTeam: "A")
        let existing = LiveScore(nhl: LiveEvent(events: [game("h1", league: .nhl), game("h2", league: .nhl)]))
        let rebuilt = LiveScore(nhl: LiveEvent(events: [orphan]))

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existing, leagues: [.nhl])

        XCTAssertEqual(result.schedule.nhl?.events.compactMap(\.idEvent), ["h1", "h2"])
    }

    func test_f1StandingsKeptWhenRebuildLostThem() {
        var existing = LiveScore(racing: LiveEvent(events: [game("r1", league: .formula1)]))
        existing.f1Standings = F1Standings(driverStandings: [], constructorStandings: [])
        let rebuilt = LiveScore()

        let result = ScheduleUpdateJob.applyingLeagueFallbacks(rebuilt: rebuilt, existing: existing, leagues: [.formula1])

        XCTAssertNotNil(result.schedule.f1Standings)
        XCTAssertEqual(result.schedule.racing?.events.compactMap(\.idEvent), ["r1"])
    }

    // MARK: - Tennis partial-failure merge

    private func tennis(_ id: String, name: String = "Wimbledon") -> Game {
        TestGameFactory.make(
            idEvent: id, idLeague: String(Leagues.atp.rawValue), strHomeTeam: "P1", strAwayTeam: "P2",
            isoDate: Date(timeIntervalSince1970: 1_780_000_000), tournamentName: name
        )
    }

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func test_tennis_allSucceeded_freshIsTheWholeTruth() {
        let merged = ScheduleUpdateJob.mergeTennisFetch(
            fresh: [tennis("1")], cached: [tennis("1"), tennis("old")], allSucceeded: true, now: now
        )
        XCTAssertEqual(merged.compactMap(\.idEvent), ["1"])
    }

    func test_tennis_partialFailure_keepsCachedGamesTheFreshSetLacks() {
        let merged = ScheduleUpdateJob.mergeTennisFetch(
            fresh: [tennis("1", name: "Fresh")], cached: [tennis("1", name: "Stale"), tennis("2")],
            allSucceeded: false, now: now
        )
        XCTAssertEqual(merged.compactMap(\.idEvent), ["1", "2"])
        XCTAssertEqual(merged.first?.tournamentName, "Fresh", "a fresh copy beats the cached one")
    }

    func test_tennis_dedupesCombinedEvents() {
        let merged = ScheduleUpdateJob.mergeTennisFetch(
            fresh: [tennis("u"), tennis("u")], cached: nil, allSucceeded: false, now: now
        )
        XCTAssertEqual(merged.compactMap(\.idEvent), ["u"])
    }
}
