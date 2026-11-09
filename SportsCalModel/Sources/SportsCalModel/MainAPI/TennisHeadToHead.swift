//
//  TennisHeadToHead.swift
//  SportsCalModel
//
//  Two players' singles meetings, as `/tennis/h2h` serves them. The server builds this
//  from ESPN's season scoreboards (every tour-level main draw since `since`), so it
//  reaches well past the month of results the app keeps.
//

import Foundation

/// One finished singles match between the two players.
public struct TennisMeeting: Codable, Equatable, Hashable, Sendable, Identifiable {
    public struct SetScore: Codable, Equatable, Hashable, Sendable {
        public var home: Int
        public var away: Int
        /// The loser's tiebreak points, when the set went to one ("7-6(5)").
        public var tiebreak: Int?

        public init(home: Int, away: Int, tiebreak: Int? = nil) {
            self.home = home
            self.away = away
            self.tiebreak = tiebreak
        }
    }

    /// ESPN's competition id.
    public var id: String
    /// The match day, yyyy-MM-dd.
    public var date: String
    public var tournament: String
    public var round: String?
    /// The players as ESPN listed them (home first).
    public var homeID: String
    public var awayID: String
    public var homeName: String
    public var awayName: String
    public var sets: [SetScore]
    /// Nil only when ESPN named no winner.
    public var winnerID: String?
    /// "ret." or "w/o" when it ended early.
    public var marker: String?

    public init(id: String, date: String, tournament: String, round: String?, homeID: String, awayID: String,
                homeName: String, awayName: String, sets: [SetScore], winnerID: String?, marker: String? = nil) {
        self.id = id
        self.date = date
        self.tournament = tournament
        self.round = round
        self.homeID = homeID
        self.awayID = awayID
        self.homeName = homeName
        self.awayName = awayName
        self.sets = sets
        self.winnerID = winnerID
        self.marker = marker
    }

    /// "6-4 7-6(5)" from `playerID`'s side (as listed when it's neither player).
    ///
    /// - Parameter playerID: The player whose games come first.
    public func scoreText(from playerID: String) -> String {
        let flip = playerID == awayID
        let text = sets.map { set in
            let (mine, theirs) = flip ? (set.away, set.home) : (set.home, set.away)
            return "\(mine)-\(theirs)" + (set.tiebreak.map { "(\($0))" } ?? "")
        }.joined(separator: " ")
        return [text, marker].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
    }

    /// The match day as a date (midnight UTC).
    public var day: Date? {
        DateParsers.parse(date + "T00:00:00Z")
    }
}

/// The meetings between `playerID` and `opponentID`, newest first.
public struct TennisHeadToHead: Codable, Equatable, Sendable {
    public var playerID: String
    public var opponentID: String
    /// Wins over each other. Walkovers aren't counted (no ball was struck), as on the tours.
    public var playerWins: Int
    public var opponentWins: Int
    public var meetings: [TennisMeeting]
    /// The first season searched.
    public var since: Int

    public init(playerID: String, opponentID: String, meetings: [TennisMeeting], since: Int) {
        self.playerID = playerID
        self.opponentID = opponentID
        let sorted = meetings.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        self.meetings = sorted
        let counted = sorted.filter { $0.marker != "w/o" }
        self.playerWins = counted.filter { $0.winnerID == playerID }.count
        self.opponentWins = counted.filter { $0.winnerID == opponentID }.count
        self.since = since
    }
}
