import Foundation
import SportsCalModel

/// Builds `/teams/competitions` from the schedule blob: every competition each team
/// has a recent or upcoming game in, plus its league's domestic cup.
///
/// Each sport's member is cut out of the blob and decoded into just the four fields
/// needed, not full `Game`s, so a rebuild is one pass over the JSON. The route caches
/// the result per calendar version (fixtures, not live ticks).
enum TeamCompetitionBuilder {
    /// Games older than this don't count: a relegated club's old league, or last
    /// season's cup run, shouldn't be followed on its behalf.
    static let lookback: TimeInterval = 300 * 24 * 3600

    private struct Member: Decodable {
        let events: [Fixture]?
    }

    private struct Fixture: Decodable {
        let idLeague: String?
        let idHomeTeam: String?
        let idAwayTeam: String?
        let dateEvent: String?
        let strTimestamp: String?
    }

    static func index(from source: String, now: Date = Date()) -> TeamCompetitionIndex {
        let bytes = Array(source.utf8)
        let ranges = CollegePayload.topLevelValueRanges(in: bytes)
        let cutoff = dayString(now.addingTimeInterval(-lookback))
        let decoder = JSONDecoder()
        var byTeam: [String: Set<Int>] = [:]

        for range in ranges.values {
            // Standings, enrichment and other non-game members simply don't decode.
            guard let member = try? decoder.decode(Member.self, from: Data(bytes[range])),
                  let events = member.events else { continue }
            for game in events {
                guard let leagueID = game.idLeague.flatMap(Int.init),
                      let league = Leagues(rawValue: leagueID),
                      !(league.isGolf || league.isTennis || league.isRacing) else { continue }
                // A game with no date can't be ruled out as old, so it counts.
                if let day = game.dateEvent ?? game.strTimestamp.map({ String($0.prefix(10)) }),
                   day.count == 10, day < cutoff { continue }
                for id in [game.idHomeTeam, game.idAwayTeam] {
                    guard let id, !id.isEmpty else { continue }
                    byTeam[id, default: []].insert(leagueID)
                }
            }
        }

        var teams: [String: [Int]] = [:]
        teams.reserveCapacity(byTeam.count)
        for (id, leagueIDs) in byTeam {
            var all = leagueIDs
            for id in leagueIDs {
                if let cup = Leagues(rawValue: id)?.domesticCup { all.insert(cup.rawValue) }
            }
            teams[id] = all.sorted()
        }
        return TeamCompetitionIndex(teams: teams)
    }

    static func body(from source: String, now: Date = Date()) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(index(from: source, now: now)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
