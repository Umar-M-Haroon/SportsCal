@testable import App
import XCTVapor
import SportsCalModel

/// Live API tests that validate schedule game counts against expected values.
/// The API returns multiple seasons of data (current + previous season).
/// Requires Redis running with populated data.
final class ScheduleCountTests: XCTestCase {

    // MARK: - Helpers

    private func games(in sport: LiveEvent?, forLeague leagueID: Int) -> [Game] {
        sport?.events.filter { $0.idLeague == "\(leagueID)" } ?? []
    }

    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    // MARK: - League Game Counts (Multi-Season)

    func testLeagueGameCounts() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            guard res.status == .ok else {
                print("Skipping: API returned \(res.status)")
                return
            }
            let schedule = try res.content.decode(LiveScore.self, using: decoder)
            let month = self.currentMonth

            // NBA (Oct–Jun): 2 seasons regular + playoffs
            if (10...12).contains(month) || (1...6).contains(month) {
                let nba = self.games(in: schedule.nba, forLeague: Leagues.nba.rawValue).count
                XCTAssertGreaterThanOrEqual(nba, 2400, "NBA should have ≥2400 games (2 seasons), got \(nba)")
                XCTAssertLessThanOrEqual(nba, 2800, "NBA should have ≤2800 games, got \(nba)")
            }

            // NHL (Oct–Jun): 2 seasons regular + playoffs
            if (10...12).contains(month) || (1...6).contains(month) {
                let nhl = self.games(in: schedule.nhl, forLeague: Leagues.nhl.rawValue).count
                XCTAssertGreaterThanOrEqual(nhl, 2600, "NHL should have ≥2600 games (2 seasons), got \(nhl)")
                XCTAssertLessThanOrEqual(nhl, 3100, "NHL should have ≤3100 games, got \(nhl)")
            }

            // MLB (Apr–Oct): full season data available after opening day
            if (4...10).contains(month) {
                let mlb = self.games(in: schedule.mlb, forLeague: Leagues.mlb.rawValue).count
                XCTAssertGreaterThanOrEqual(mlb, 2400, "MLB should have ≥2400 games during season, got \(mlb)")
            }

            // NFL (Sep–Feb): 2 seasons regular + playoffs
            if (9...12).contains(month) || (1...2).contains(month) {
                let nfl = self.games(in: schedule.nfl, forLeague: Leagues.nfl.rawValue).count
                XCTAssertGreaterThanOrEqual(nfl, 272, "NFL should have ≥272 games, got \(nfl)")
            }

            // Soccer domestic leagues (2 seasons): Aug–May
            if (8...12).contains(month) || (1...5).contains(month) {
                let epl = self.games(in: schedule.soccer, forLeague: Leagues.English_Premier_League.rawValue).count
                XCTAssertGreaterThanOrEqual(epl, 760, "EPL should have ≥760 games (2×380), got \(epl)")
                XCTAssertLessThanOrEqual(epl, 770, "EPL should have ≤770 games, got \(epl)")

                let laLiga = self.games(in: schedule.soccer, forLeague: Leagues.La_Liga.rawValue).count
                XCTAssertGreaterThanOrEqual(laLiga, 760, "La Liga should have ≥760 games (2×380), got \(laLiga)")
                XCTAssertLessThanOrEqual(laLiga, 770, "La Liga should have ≤770 games, got \(laLiga)")

                let serieA = self.games(in: schedule.soccer, forLeague: Leagues.Serie_A.rawValue).count
                XCTAssertGreaterThanOrEqual(serieA, 760, "Serie A should have ≥760 games (2×380), got \(serieA)")
                XCTAssertLessThanOrEqual(serieA, 770, "Serie A should have ≤770 games, got \(serieA)")

                let bundesliga = self.games(in: schedule.soccer, forLeague: Leagues.German_Bundesliga.rawValue).count
                XCTAssertGreaterThanOrEqual(bundesliga, 612, "Bundesliga should have ≥612 games (2×306), got \(bundesliga)")
                XCTAssertLessThanOrEqual(bundesliga, 620, "Bundesliga should have ≤620 games, got \(bundesliga)")

                let ligue1 = self.games(in: schedule.soccer, forLeague: Leagues.Ligue_1.rawValue).count
                XCTAssertGreaterThanOrEqual(ligue1, 612, "Ligue 1 should have ≥612 games (2×306), got \(ligue1)")
                XCTAssertLessThanOrEqual(ligue1, 620, "Ligue 1 should have ≤620 games, got \(ligue1)")

                let eredivisie = self.games(in: schedule.soccer, forLeague: Leagues.Eredivisie.rawValue).count
                XCTAssertGreaterThanOrEqual(eredivisie, 612, "Eredivisie should have ≥612 games (2×306), got \(eredivisie)")
                XCTAssertLessThanOrEqual(eredivisie, 650, "Eredivisie should have ≤650 games, got \(eredivisie)")
            }
        })
    }

    // MARK: - Variable League Ranges

    func testVariableLeagueRanges() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            guard res.status == .ok else {
                print("Skipping: API returned \(res.status)")
                return
            }
            let schedule = try res.content.decode(LiveScore.self, using: decoder)

            // F1 (Mar–Dec): 2 seasons × ~24 races
            if (3...12).contains(self.currentMonth) {
                let f1 = self.games(in: schedule.racing, forLeague: Leagues.formula1.rawValue).count
                XCTAssertGreaterThanOrEqual(f1, 22, "F1 should have ≥22 events, got \(f1)")
                XCTAssertLessThanOrEqual(f1, 50, "F1 should have ≤50 events, got \(f1)")
            }

            // PGA: multi-season tournaments
            let pga = self.games(in: schedule.golf, forLeague: Leagues.pga.rawValue).count
            XCTAssertGreaterThanOrEqual(pga, 80, "PGA should have ≥80 events, got \(pga)")
            XCTAssertLessThanOrEqual(pga, 300, "PGA should have ≤300 events, got \(pga)")

            // ATP: individual matches (not tournaments)
            let atp = self.games(in: schedule.tennis, forLeague: Leagues.atp.rawValue).count
            XCTAssertGreaterThanOrEqual(atp, 10000, "ATP should have ≥10000 matches, got \(atp)")
            XCTAssertLessThanOrEqual(atp, 50000, "ATP should have ≤50000 matches, got \(atp)")

            // WTA: individual matches (not tournaments)
            let wta = self.games(in: schedule.tennis, forLeague: Leagues.wta.rawValue).count
            XCTAssertGreaterThanOrEqual(wta, 10000, "WTA should have ≥10000 matches, got \(wta)")
            XCTAssertLessThanOrEqual(wta, 60000, "WTA should have ≤60000 matches, got \(wta)")

            // UCL: multi-season with qualifying rounds
            let ucl = self.games(in: schedule.soccer, forLeague: Leagues.UEFA_Champions_League.rawValue).count
            XCTAssertGreaterThanOrEqual(ucl, 200, "UCL should have ≥200 events, got \(ucl)")
            XCTAssertLessThanOrEqual(ucl, 600, "UCL should have ≤600 events, got \(ucl)")

            // Cup competitions
            let cups: [Leagues] = [
                .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
                .UEFA_Europa_League, .UEFA_Conference_League
            ]
            for cup in cups {
                let count = self.games(in: schedule.soccer, forLeague: cup.rawValue).count
                XCTAssertGreaterThan(count, 0, "\(cup.leagueName) should have > 0 games, got \(count)")
            }
        })
    }

    // MARK: - Per-Sport Endpoint Consistency

    func testPerSportEndpointConsistency() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()

        try app.test(.GET, "schedules", afterResponse: { schedulesRes in
            guard schedulesRes.status == .ok else {
                print("Skipping: schedules returned \(schedulesRes.status)")
                return
            }
            let schedule = try schedulesRes.content.decode(LiveScore.self, using: decoder)

            let sportMapping: [(slug: String, count: Int)] = [
                ("basketball", schedule.nba?.events.count ?? 0),
                ("hockey", schedule.nhl?.events.count ?? 0),
                ("baseball", schedule.mlb?.events.count ?? 0),
                ("football", schedule.nfl?.events.count ?? 0),
                ("soccer", schedule.soccer?.events.count ?? 0),
                ("golf", schedule.golf?.events.count ?? 0),
                ("tennis", schedule.tennis?.events.count ?? 0),
                ("racing", schedule.racing?.events.count ?? 0),
            ]

            for (slug, expectedCount) in sportMapping {
                try app.test(.GET, "sport/\(slug)", afterResponse: { sportRes in
                    guard sportRes.status == .ok else {
                        print("Skipping /sport/\(slug): returned \(sportRes.status)")
                        return
                    }
                    let liveEvent = try sportRes.content.decode(LiveEvent.self, using: decoder)
                    XCTAssertEqual(
                        liveEvent.events.count, expectedCount,
                        "/sport/\(slug) count (\(liveEvent.events.count)) should match /schedules count (\(expectedCount))"
                    )
                })
            }
        })
    }

    // MARK: - Data Integrity

    func testAllGamesHaveRequiredFields() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            guard res.status == .ok else {
                print("Skipping: API returned \(res.status)")
                return
            }
            let schedule = try res.content.decode(LiveScore.self, using: decoder)

            let allEvents = [
                schedule.nba, schedule.nfl, schedule.nhl, schedule.mlb,
                schedule.soccer, schedule.golf, schedule.tennis, schedule.racing
            ].compactMap { $0 }.flatMap { $0.events }

            let validLeagueIDs = Set(Leagues.allCases.map { "\($0.rawValue)" })

            for game in allEvents {
                guard let leagueID = game.idLeague else {
                    XCTFail("Game \(game.strHomeTeam) vs \(game.strAwayTeam) has nil idLeague")
                    continue
                }
                XCTAssertTrue(
                    validLeagueIDs.contains(leagueID),
                    "Unknown idLeague \(leagueID): \(game.strHomeTeam) vs \(game.strAwayTeam)"
                )

                XCTAssertNotNil(game.strTimestamp, "Game missing strTimestamp (league \(leagueID))")

                if !game.isIndividualSport {
                    XCTAssertFalse(game.strHomeTeam.isEmpty, "Empty home team (league \(leagueID))")
                    XCTAssertFalse(game.strAwayTeam.isEmpty, "Empty away team (league \(leagueID))")
                }
            }
        })
    }

    func testSoccerLeagueBreakdown() async throws {
        let app = Application(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)

        let decoder = JSONDecoder()
        try app.test(.GET, "schedules", afterResponse: { res in
            guard res.status == .ok else {
                print("Skipping: API returned \(res.status)")
                return
            }
            let schedule = try res.content.decode(LiveScore.self, using: decoder)

            guard let soccerEvents = schedule.soccer?.events else {
                print("Skipping: no soccer events in schedule")
                return
            }

            let byLeague = Dictionary(grouping: soccerEvents) { $0.idLeague ?? "unknown" }

            let soccerLeagues: [Leagues] = [
                .English_Premier_League, .La_Liga, .Serie_A, .German_Bundesliga,
                .Ligue_1, .Eredivisie, .MLS, .Liga_MX,
                .UEFA_Champions_League, .UEFA_Europa_League, .UEFA_Conference_League,
                .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
                .English_League_Championship
            ]

            for league in soccerLeagues {
                let key = "\(league.rawValue)"
                let count = byLeague[key]?.count ?? 0
                XCTAssertGreaterThan(
                    count, 0,
                    "\(league.leagueName) should have > 0 games in soccer, got \(count)"
                )
            }
        })
    }
}
