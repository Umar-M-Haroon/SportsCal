//
//  GolfEnrichment.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 4/11/26.
//

import Foundation

// MARK: - Golf Course Info

public struct GolfCourseInfo: Codable, Equatable, Hashable {
    public let courseName: String
    public let par: Int
    public let holePars: [Int]?
    /// Tournament context from ESPN's golf leaderboard feed (`GolfEnrichmentJob`). All
    /// optional: the scoreboard alone fills none of them.
    /// "$6,000,000".
    public var purse: String?
    public var defendingChampion: String?
    /// Rounds the event is scheduled for (4 on most tours, 3 on LIV).
    public var numberOfRounds: Int?
    /// The round after which the cut is made, the (projected while that round is being
    /// played) cut score to par, and how many players are inside it.
    public var cutRound: Int?
    public var cutScore: Int?
    public var cutCount: Int?
    public var yardage: Int?

    public init(courseName: String, par: Int, holePars: [Int]? = nil, purse: String? = nil, defendingChampion: String? = nil,
                numberOfRounds: Int? = nil, cutRound: Int? = nil, cutScore: Int? = nil, cutCount: Int? = nil, yardage: Int? = nil) {
        self.courseName = courseName
        self.par = par
        self.holePars = holePars
        self.purse = purse
        self.defendingChampion = defendingChampion
        self.numberOfRounds = numberOfRounds
        self.cutRound = cutRound
        self.cutScore = cutScore
        self.cutCount = cutCount
        self.yardage = yardage
    }

    /// This course info with `other`'s tournament context filled in where this has none.
    public func withContext(from other: GolfCourseInfo?) -> GolfCourseInfo {
        guard let other else { return self }
        var merged = self
        merged.purse = purse ?? other.purse
        merged.defendingChampion = defendingChampion ?? other.defendingChampion
        merged.numberOfRounds = numberOfRounds ?? other.numberOfRounds
        merged.cutRound = cutRound ?? other.cutRound
        merged.cutScore = cutScore ?? other.cutScore
        merged.cutCount = cutCount ?? other.cutCount
        merged.yardage = yardage ?? other.yardage
        return merged
    }
}

// MARK: - Golf Round Stats

public struct GolfRoundStats: Codable, Equatable, Hashable {
    public let fairways: String?
    public let greensInRegulation: String?
    public let putts: Int?
    public let birdies: Int?
    public let bogeys: Int?
    public let eagles: Int?
    public let pars: Int?

    public init(fairways: String? = nil, greensInRegulation: String? = nil, putts: Int? = nil, birdies: Int? = nil, bogeys: Int? = nil, eagles: Int? = nil, pars: Int? = nil) {
        self.fairways = fairways
        self.greensInRegulation = greensInRegulation
        self.putts = putts
        self.birdies = birdies
        self.bogeys = bogeys
        self.eagles = eagles
        self.pars = pars
    }
}

// MARK: - Golf Hole Score

public struct GolfHoleScore: Codable, Equatable, Hashable {
    public let hole: Int
    public let par: Int
    public let score: Int?

    public init(hole: Int, par: Int, score: Int? = nil) {
        self.hole = hole
        self.par = par
        self.score = score
    }

    public var relativeToPar: Int? {
        guard let score else { return nil }
        return score - par
    }
}

// MARK: - Golf Round Detail

public struct GolfRoundDetail: Codable, Equatable, Hashable {
    public let roundNumber: Int
    public let totalScore: Int?
    public let stats: GolfRoundStats?
    public var holeScores: [GolfHoleScore]?

    public init(roundNumber: Int, totalScore: Int? = nil, stats: GolfRoundStats? = nil, holeScores: [GolfHoleScore]? = nil) {
        self.roundNumber = roundNumber
        self.totalScore = totalScore
        self.stats = stats
        self.holeScores = holeScores
    }
}
