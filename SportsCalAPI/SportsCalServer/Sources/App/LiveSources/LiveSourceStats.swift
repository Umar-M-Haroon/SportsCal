//
//  LiveSourceStats.swift
//
//  Which live source is actually fastest. Every tick, each source reports the score it
//  has for each in-progress game; when a source's score for a game changes, that change
//  is either a new sighting (this source got there first) or a catch-up to a change
//  another source already reported (this source lagged by the gap). Over a slate of
//  games that settles "is the official feed / a paid feed worth it" with numbers rather
//  than guesses.
//
//  Resolution is the LiveTicker cadence (~5s): two sources that both have a change by
//  the same tick tie at lag 0. Pure value type — the ticker loads, records, and saves it
//  under its own job lock, so there is exactly one writer.
//

import Foundation

struct LiveSourceStats: Codable, Equatable, Sendable {
    struct SourceRecord: Codable, Equatable, Sendable {
        /// Score changes this source reported before any other source did.
        var wins = 0
        /// Score changes this source reported after another source already had them.
        var follows = 0
        var totalLagSeconds: Double = 0
        var maxLagSeconds: Double = 0
        /// Copies dropped because they were behind the snapshot (LiveMerge.shouldAccept).
        var behind = 0

        var averageLagSeconds: Double { follows == 0 ? 0 : totalLagSeconds / Double(follows) }
    }

    /// One contested score change, for the admin dashboard's recent list.
    struct Race: Codable, Equatable, Sendable {
        var eventID: String
        var score: String
        var first: String
        var at: Date
        /// Other sources that caught up, with their lag in seconds.
        var followers: [String: Double]
    }

    private struct Sighting: Codable, Equatable, Sendable {
        var first: String
        var at: Date
        var seenBy: Set<String>
    }

    private struct LastSeen: Codable, Equatable, Sendable {
        var score: String
        var at: Date
    }

    private(set) var sources: [String: SourceRecord] = [:]
    private(set) var recent: [Race] = []
    private(set) var since: Date
    /// "eventID|score" → the first source to report it.
    private var sightings: [String: Sighting] = [:]
    /// "source|eventID" → the last score that source reported for the game.
    private var lastSeen: [String: LastSeen] = [:]

    static let recentLimit = 50
    /// A change nobody else reports within this window was uncontested; stop waiting.
    static let sightingWindow: TimeInterval = 10 * 60
    /// Games not seen for this long are over; drop their per-source state.
    static let lastSeenWindow: TimeInterval = 6 * 3600

    init(since: Date) {
        self.since = since
    }

    /// Records one source's pass over the snapshot: the score it reported per snapshot
    /// `idEvent` (LiveMerge.Result.observedScores) and how many copies it had behind.
    mutating func record(source: String, observed: [String: String], behindCount: Int, now: Date) {
        sources[source, default: SourceRecord()].behind += behindCount

        for (eventID, score) in observed {
            let seenKey = "\(source)|\(eventID)"
            let previous = lastSeen[seenKey]?.score
            lastSeen[seenKey] = LastSeen(score: score, at: now)
            // A source's first look at a game is not a change; nor is the same score again.
            guard let previous, previous != score else { continue }

            let key = "\(eventID)|\(score)"
            if var sighting = sightings[key] {
                guard !sighting.seenBy.contains(source) else { continue }
                let lag = max(0, now.timeIntervalSince(sighting.at))
                if sighting.seenBy.count == 1 {
                    // First follower: the race is contested, so the first source won it.
                    sources[sighting.first, default: SourceRecord()].wins += 1
                }
                var record = sources[source, default: SourceRecord()]
                record.follows += 1
                record.totalLagSeconds += lag
                record.maxLagSeconds = max(record.maxLagSeconds, lag)
                sources[source] = record
                sighting.seenBy.insert(source)
                sightings[key] = sighting
                noteFollower(eventID: eventID, score: score, first: sighting.first, at: sighting.at, follower: source, lag: lag)
            } else {
                sightings[key] = Sighting(first: source, at: now, seenBy: [source])
            }
        }
        prune(now: now)
    }

    private mutating func noteFollower(eventID: String, score: String, first: String, at: Date, follower: String, lag: Double) {
        if let index = recent.firstIndex(where: { $0.eventID == eventID && $0.score == score }) {
            recent[index].followers[follower] = lag
        } else {
            recent.insert(Race(eventID: eventID, score: score, first: first, at: at, followers: [follower: lag]), at: 0)
            if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        }
    }

    private mutating func prune(now: Date) {
        sightings = sightings.filter { now.timeIntervalSince($0.value.at) < Self.sightingWindow }
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value.at) < Self.lastSeenWindow }
    }

    // MARK: - Storage

    static func key(isDebug: Bool) -> String { (isDebug ? "debug-" : "") + "Live Source Stats" }
    /// Snapshot `idEvent` → the source name pinned for that game by an admin.
    static func forcedSourcesKey(isDebug: Bool) -> String { (isDebug ? "debug-" : "") + "Live Forced Sources" }
}
