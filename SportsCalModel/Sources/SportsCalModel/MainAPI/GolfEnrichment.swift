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

    public init(courseName: String, par: Int, holePars: [Int]? = nil) {
        self.courseName = courseName
        self.par = par
        self.holePars = holePars
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
    public let holeScores: [GolfHoleScore]?

    public init(roundNumber: Int, totalScore: Int? = nil, stats: GolfRoundStats? = nil, holeScores: [GolfHoleScore]? = nil) {
        self.roundNumber = roundNumber
        self.totalScore = totalScore
        self.stats = stats
        self.holeScores = holeScores
    }
}
