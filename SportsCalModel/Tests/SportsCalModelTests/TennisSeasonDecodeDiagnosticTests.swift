import XCTest
@testable import SportsCalModel

/// Diagnostic: replays the server's structured-tennis build (DBUpdatejob `.atp/.wta` case)
/// against real ESPN season payloads to see whether recent tournaments survive decode.
/// Skipped unless TENNIS_FIXTURE_DIR points at a directory of downloaded scoreboards.
final class TennisSeasonDecodeDiagnosticTests: XCTestCase {
    func testSeasonPayloadsProduceRecentTournaments() throws {
        guard let dir = ProcessInfo.processInfo.environment["TENNIS_FIXTURE_DIR"] else {
            throw XCTSkip("TENNIS_FIXTURE_DIR not set")
        }
        let cases: [(String, Leagues)] = [
            ("atp2025.json", .atp), ("atp2026.json", .atp),
            ("wta2025.json", .wta), ("wta2026.json", .wta),
        ]
        var all: [Game] = []
        for (file, league) in cases {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
            let data = try Data(contentsOf: url)
            let board: Scoreboard
            do {
                board = try JSONDecoder().decode(Scoreboard.self, from: data)
            } catch {
                XCTFail("DECODE FAILED \(file): \(error)")
                continue
            }
            guard let parsed = LiveEvent(events: board, league: league) else {
                print("LIVEEVENT NIL for \(file) (scoreboard events: \(board.events.count))")
                continue
            }
            print("\(file): scoreboardEvents=\(board.events.count) games=\(parsed.events.count)")
            all.append(contentsOf: parsed.events)
        }
        var seen = Set<String>()
        all = all.filter { g in guard let id = g.idEvent else { return true }; return seen.insert(id).inserted }
        let dates = all.compactMap { $0.isoDate }
        print("TOTAL games=\(all.count) max date=\(String(describing: dates.max()))")
        let names = Set(all.compactMap { $0.tournamentName })
        print("US Open present: \(names.contains { $0.localizedCaseInsensitiveContains("US Open") })")
        print("Cincinnati present: \(names.contains { $0.localizedCaseInsensitiveContains("Cincinnati") })")
        let aug = all.filter { g in
            guard let d = g.isoDate else { return false }
            return d >= Date(timeIntervalSince1970: 1755993600) // 2026-08-24
        }
        print("games on/after 2026-08-24: \(aug.count)")
    }
}
