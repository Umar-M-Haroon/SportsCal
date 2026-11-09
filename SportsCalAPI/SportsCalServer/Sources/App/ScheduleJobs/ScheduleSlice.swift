//
//  ScheduleSlice.swift
//
//  `/schedules/sports/:key` bodies (one sport's part of the schedule) and the full golf
//  leaderboards the slimmed schedule points to.
//

import Foundation
import Vapor
import SportsCalModel

enum ScheduleSlice {
    /// `{"<member>":<value>,…}` for `key`'s members, copied byte-for-byte out of the
    /// stored schedule JSON. A member the schedule doesn't have is left out, so a sport
    /// with no games reads as an empty `LiveScore` rather than an error.
    static func body(for key: LiveScore.WireKey, in source: String) -> String {
        let bytes = Array(source.utf8)
        let ranges = CollegePayload.topLevelValueRanges(in: bytes)
        var out: [UInt8] = [UInt8(ascii: "{")]
        for member in key.members {
            guard let range = ranges[member] else { continue }
            if out.count > 1 { out.append(UInt8(ascii: ",")) }
            out.append(contentsOf: Array("\"\(member)\":".utf8))
            out.append(contentsOf: bytes[range])
        }
        out.append(UInt8(ascii: "}"))
        return String(decoding: out, as: UTF8.self)
    }
}

/// A golf tournament with its whole field and scorecards, straight from ESPN's board for
/// that event (the schedule and live feed carry the top `LiveEvent.golfFieldLimit`), plus
/// the leaderboard feed's purse / cut / defending champion. Finished tournaments don't
/// change, so they're cached for a week; live ones for a minute.
enum GolfTournamentDetail {
    static func game(league: Leagues, eventID: String, app: Application) async throws -> Game {
        let key = "Golf Tournament v2 \(league.rawValue)-\(eventID)"
        if let cached = try? await app.kv.getJSON(key, as: Game.self) { return cached }

        guard let slug = league.espnSlug else { throw Abort(.notFound) }
        let url = "https://site.api.espn.com/apis/site/v2/sports/golf/\(slug)/scoreboard?event=\(eventID)"
        let response = try await ESPNNetworking.performGet(app.client, URI(string: url))
        let board = try response.content.decode(Scoreboard.self)
        let events = LiveEvent(events: board, league: league, golfFieldLimit: nil)?.events ?? []
        guard var game = events.first(where: { $0.idEvent == eventID }) ?? events.first else {
            throw Abort(.notFound)
        }
        if let leaderboard = try? await ESPNNetworking.getGolfLeaderboard(req: app.client, eventId: eventID, tour: league),
           let info = GolfEnrichmentJob.courseInfo(from: leaderboard, eventID: eventID) {
            game = GolfEnrichmentJob.applying(info, to: game)
        }
        let final = ScheduleCalendarVersion.state(of: game) == .final
        try? await app.kv.setJSON(key, value: game, ttl: final ? 7 * 24 * 3600 : 60)
        return game
    }
}
