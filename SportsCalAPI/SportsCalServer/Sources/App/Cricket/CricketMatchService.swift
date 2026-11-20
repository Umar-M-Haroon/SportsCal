//
//  CricketMatchService.swift
//
//  `/cricket/match/:eventID`: one match's scorecard (batting and bowling per innings),
//  built from ESPN's per-event summary by `ESPNCricketSummary.scorecard(eventID:)`.
//  Cached like the soccer match centre: 30s while live, a day once final.
//

import Foundation
import Vapor
import SportsCalModel

enum CricketMatchService {
    /// Any carried league id serves any cricket event's summary (ESPN keys the summary
    /// by event); IPL's is stable.
    static let summaryLeagueID = 8048
    static let missCacheSeconds: TimeInterval = 2 * 60

    static func cacheKey(eventID: String, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "Cricket Match-\(eventID)"
    }

    static func missKey(eventID: String, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "Cricket Match Miss-\(eventID)"
    }

    /// ESPN event ids are all digits; anything else never reaches ESPN.
    static func isValidEventID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 20 && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber)
    }

    /// The scorecard, or nil when ESPN has none yet (before the toss) or the fetch failed.
    static func scorecard(app: Application, eventID: String) async -> CricketScorecard? {
        let isDebug = app.environment == .development
        let key = cacheKey(eventID: eventID, isDebug: isDebug)
        if let cached = try? await app.kv.getJSON(key, as: CricketScorecard.self) { return cached }
        if (try? await app.kv.exists(missKey(eventID: eventID, isDebug: isDebug))) == true { return nil }

        return await CricketMatchFetches.shared.run(eventID: eventID) {
            let data: Data
            do {
                let uri = URI(string: "https://site.api.espn.com/apis/site/v2/sports/cricket/\(summaryLeagueID)/summary?event=\(eventID)")
                let response = try await ESPNNetworking.performGet(app.client, uri)
                guard let body = response.body else { return nil }
                data = Data(buffer: body)
            } catch {
                // ESPN failed: try again next time rather than remembering a miss.
                app.logger.warning("Cricket match fetch failed for \(eventID): \(error)")
                return nil
            }
            let decoder = JSONDecoder()
            guard let summary = try? decoder.decode(ESPNCricketSummary.self, from: data),
                  let card = summary.scorecard(eventID: eventID) else {
                try? await app.kv.setString(missKey(eventID: eventID, isDebug: isDebug), value: "1", ttl: missCacheSeconds)
                return nil
            }
            let state = (try? decoder.decode(SummaryState.self, from: data))?.state
            try? await app.kv.setJSON(key, value: card, ttl: TimeInterval(SoccerMatchService.cacheSeconds(state: state)))
            return card
        }
    }

    /// Just the match state out of the same summary, for the cache lifetime.
    struct SummaryState: Decodable {
        struct Header: Decodable { var competitions: [ESPNCricketBoard.Match]? }
        var header: Header?
        var state: String? { header?.competitions?.first?.status?.type?.state }
    }
}

/// One ESPN fetch per event however many apps open it at once.
actor CricketMatchFetches {
    static let shared = CricketMatchFetches()
    private var inFlight: [String: Task<CricketScorecard?, Never>] = [:]

    func run(eventID: String, fetch: @escaping @Sendable () async -> CricketScorecard?) async -> CricketScorecard? {
        if let running = inFlight[eventID] { return await running.value }
        let task = Task { await fetch() }
        inFlight[eventID] = task
        let result = await task.value
        inFlight[eventID] = nil
        return result
    }
}
