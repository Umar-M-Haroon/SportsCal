//
//  LivePlayerFeed.swift
//  App
//
//  What custom player alerts read for one game: who made each play and every
//  player's live numbers. Built from the ESPN summary `ESPNFetchJob` already fetches
//  each tick for play-by-play, so it costs no extra ESPN requests.
//
//  Server-side only, at `LivePlayers-{espnEventID}`. Nothing serves it: not
//  `/schedules`, not the live socket, not `/plays` (whose plays drop participants;
//  see `CachedPlays`). Participants would grow a game's served plays by 20–50%.
//

import Foundation
import SportsCalModel

struct LivePlayerFeed: Codable, Equatable {
    /// The plays that name an athlete, oldest first.
    struct PlayAthletes: Codable, Equatable {
        var playID: String
        var participants: [PlayParticipant]
        /// Who earned which alert play type in this play (`PlayHighlight.highlights`),
        /// classified here while the play text is at hand. Nil in feeds written before
        /// custom alerts.
        var highlights: [PlayHighlight]? = nil
    }

    var espnEventID: String
    /// The TheSportsDB event the client knows this game by, where the schedule has one.
    var tsdbEventID: String?
    /// ESPN slugs: "basketball" / "nba".
    var sport: String
    var league: String
    var fetchedAt: Date
    var isFinal: Bool
    var plays: [PlayAthletes]
    var statLines: [PlayerLiveStatLine]
    /// Athlete ID → the line fantasy scoring reads: the box score plus field goals by
    /// distance and two-point conversions (`FantasyStatLines`). Sports fantasy scores
    /// only; nil in feeds written before fantasy alerts.
    var fantasyStats: [String: [String: Double]]? = nil

    /// Long enough to outlast a quiet stretch with no new plays (a rain delay: the
    /// job only re-fetches when the last play changes), short enough that finals
    /// clear out the same evening. Alerts only care about games in progress.
    static let ttlSeconds = 6 * 60 * 60

    /// Nil when the summary has neither (soccer, a game that hasn't started).
    init?(
        summary: ESPNSummaryResponse,
        sportType: SportType?,
        espnEventID: String,
        tsdbEventID: String?,
        sport: String,
        league: String,
        isFinal: Bool,
        fetchedAt: Date
    ) {
        let lines = sportType.map(summary.playerStatLines(sport:)) ?? []
        // Full names decide a basketball block's blocker ("Rudy Gobert blocks …").
        var fullNames: [String: String] = [:]
        for line in lines where fullNames[line.athleteID] == nil { fullNames[line.athleteID] = line.name }
        let plays = summary.allPlaysWithNamedParticipants.compactMap { play -> PlayAthletes? in
            guard let participants = play.participants, !participants.isEmpty else { return nil }
            let highlights = sportType.map { PlayHighlight.highlights(in: play, sport: $0, fullNames: fullNames) } ?? []
            return PlayAthletes(playID: play.id, participants: participants, highlights: highlights.isEmpty ? nil : highlights)
        }
        guard !plays.isEmpty || !lines.isEmpty else { return nil }
        self.espnEventID = espnEventID
        self.tsdbEventID = tsdbEventID
        self.sport = sport
        self.league = league
        self.fetchedAt = fetchedAt
        self.isFinal = isFinal
        self.plays = plays
        self.statLines = lines
        if let sportType, FantasyScoring.supports(sportType) {
            let fantasy = FantasyStatLines.lines(summary: summary, sport: sportType, eventID: espnEventID)
            var byAthlete: [String: [String: Double]] = [:]
            for line in fantasy where !line.isDST { byAthlete[line.athleteID] = line.stats }
            fantasyStats = byAthlete.isEmpty ? nil : byAthlete
        }
    }
}
