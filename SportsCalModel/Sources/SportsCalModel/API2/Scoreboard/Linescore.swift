// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let linescore = try? newJSONDecoder().decode(Linescore.self, from: jsonData)

import Foundation

// MARK: - Linescore
public struct Linescore: Codable {
    public var value: Double?
    public var displayValue: String?
    public var period: Int?
    public var linescores: [HoleLinescore]?
    public var statistics: LinescoreStatistics?
    public var scoreType: ScoreType?

    public init(value: Double?, displayValue: String? = nil, period: Int? = nil, linescores: [HoleLinescore]? = nil, statistics: LinescoreStatistics? = nil, scoreType: ScoreType? = nil) {
        self.value = value
        self.displayValue = displayValue
        self.period = period
        self.linescores = linescores
        self.statistics = statistics
        self.scoreType = scoreType
    }
}

// MARK: - Hole-level linescore (nested inside round linescores for golf)
public struct HoleLinescore: Codable {
    public var value: Double?
    public var displayValue: String?
    public var period: Int?
    public var scoreType: ScoreType?
}

// MARK: - Score type (par-relative for golf)
public struct ScoreType: Codable {
    public var displayValue: String?
}

// MARK: - Per-round statistics (nested inside round linescores for golf)
public struct LinescoreStatistics: Codable {
    public var categories: [LinescoreStatCategory]?
}

public struct LinescoreStatCategory: Codable {
    public var stats: [LinescoreStatEntry]?
}

public struct LinescoreStatEntry: Codable {
    public var value: Double?
    public var displayValue: String?
}
