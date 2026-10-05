//
//  CollegePayload.swift
//
//  College football is opt-in on the wire. The model's `LiveScore` Codable already puts
//  every college game under its own top-level `ncaaf` key; this strips that key from
//  LiveScore-shaped responses unless the request asks for college with `cfb=1`.
//
//  Clients that predate college football ignore the key, but still download it: ~1.4MB
//  on /schedules and ~200KB on every uncompressed /ws frame on a busy Saturday. So does
//  any current client with college switched off.
//

import Foundation
import Vapor
import SportsCalModel

enum CollegePayload {
    /// Whether the request opted into college football (`cfb=1`).
    static func wantsCollege(_ req: Request) -> Bool {
        (try? req.query.get(String.self, at: "cfb")) == "1"
    }

    /// `json` as this request should see it. The stripped copy is derived once per
    /// change of `json` (keyed by `variant`), so the default path stays a cached string
    /// rather than a per-request decode and re-encode of a multi-MB blob.
    static func serve(_ json: String, for req: Request, variant: String) -> String {
        if wantsCollege(req) { return json }
        return withoutCollege(json, variant: variant)
    }

    /// The college-free copy of `json`, memoized per `variant`.
    static func withoutCollege(_ json: String, variant: String) -> String {
        StrippedMemo.fixed.value(for: variant, source: json, build: strippingCollege)
    }

    /// The college-free copy of one `/schedules/date` day, memoized in a small bounded
    /// memo — dates are client-chosen, so they can't each get a permanent entry.
    static func withoutCollege(day json: String, date: Int) -> String {
        StrippedMemo.days.value(for: "\(date)", source: json, build: strippingCollege)
    }

    /// Removes the top-level `"ncaaf"` member from a JSON object, leaving every other
    /// byte exactly as it was. Returns `json` unchanged when there is no such member, or
    /// when the input isn't a JSON object this scanner can walk.
    ///
    /// A single linear pass over the bytes: no decode, no re-encode, and key order is
    /// irrelevant (JSONEncoder doesn't guarantee one).
    static func strippingCollege(_ json: String) -> String {
        var bytes = Array(json.utf8)
        guard let range = topLevelMemberRange(named: "ncaaf", in: bytes) else { return json }
        bytes.removeSubrange(range)
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Scanner

    private static let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
    private static let openBrace = UInt8(ascii: "{"), closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]")
    private static let comma = UInt8(ascii: ","), colon = UInt8(ascii: ":")

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    private static func skipWhitespace(_ b: [UInt8], _ i: inout Int) {
        while i < b.count, isWhitespace(b[i]) { i += 1 }
    }

    /// `i` at an opening quote → just past the closing one. False if unterminated.
    private static func skipString(_ b: [UInt8], _ i: inout Int) -> Bool {
        guard i < b.count, b[i] == quote else { return false }
        i += 1
        while i < b.count {
            if b[i] == backslash { i += 2; continue }
            if b[i] == quote { i += 1; return true }
            i += 1
        }
        return false
    }

    /// `i` at a value's first byte → just past the value.
    private static func skipValue(_ b: [UInt8], _ i: inout Int) -> Bool {
        guard i < b.count else { return false }
        switch b[i] {
        case quote:
            return skipString(b, &i)
        case openBrace, openBracket:
            var depth = 0
            while i < b.count {
                switch b[i] {
                case quote:
                    guard skipString(b, &i) else { return false }
                    continue
                case openBrace, openBracket:
                    depth += 1
                case closeBrace, closeBracket:
                    depth -= 1
                    if depth == 0 { i += 1; return true }
                default:
                    break
                }
                i += 1
            }
            return false
        default:
            // Number, true, false, null.
            while i < b.count, b[i] != comma, b[i] != closeBrace, b[i] != closeBracket, !isWhitespace(b[i]) { i += 1 }
            return true
        }
    }

    /// The value range of every top-level member of a JSON object, in one pass. Empty
    /// when `b` isn't an object this scanner can walk.
    static func topLevelValueRanges(in b: [UInt8]) -> [String: Range<Int>] {
        var ranges: [String: Range<Int>] = [:]
        var i = 0
        skipWhitespace(b, &i)
        guard i < b.count, b[i] == openBrace else { return [:] }
        i += 1
        while true {
            skipWhitespace(b, &i)
            guard i < b.count, b[i] != closeBrace else { return ranges }
            let keyStart = i
            guard skipString(b, &i) else { return [:] }
            let key = String(decoding: b[(keyStart + 1)..<(i - 1)], as: UTF8.self)
            skipWhitespace(b, &i)
            guard i < b.count, b[i] == colon else { return [:] }
            i += 1
            skipWhitespace(b, &i)
            let valueStart = i
            guard skipValue(b, &i) else { return [:] }
            ranges[key] = valueStart..<i
            skipWhitespace(b, &i)
            guard i < b.count, b[i] == comma else { return ranges }
            i += 1
        }
    }

    /// The byte range to delete to remove the top-level member `name`, including exactly
    /// one of its neighbouring commas so the object stays valid.
    static func topLevelMemberRange(named name: String, in b: [UInt8]) -> Range<Int>? {
        let target = Array(name.utf8)
        var i = 0
        skipWhitespace(b, &i)
        guard i < b.count, b[i] == openBrace else { return nil }
        i += 1
        var previousComma: Int?
        while true {
            skipWhitespace(b, &i)
            guard i < b.count, b[i] != closeBrace else { return nil }
            let memberStart = i
            guard skipString(b, &i) else { return nil }
            let key = b[(memberStart + 1)..<(i - 1)]
            skipWhitespace(b, &i)
            guard i < b.count, b[i] == colon else { return nil }
            i += 1
            skipWhitespace(b, &i)
            guard skipValue(b, &i) else { return nil }
            let valueEnd = i
            skipWhitespace(b, &i)
            let followingComma = (i < b.count && b[i] == comma) ? i : nil

            if key.elementsEqual(target) {
                if let previousComma { return previousComma..<valueEnd }
                if let followingComma {
                    var next = followingComma + 1
                    skipWhitespace(b, &next)
                    return memberStart..<next
                }
                return memberStart..<valueEnd
            }
            guard let followingComma else { return nil }
            previousComma = followingComma
            i = followingComma + 1
        }
    }
}

/// Last source and its stripped copy, per variant.
///
/// Built for the `/schedules` hot path, which every client hits at launch: no actor hop
/// (requests aren't serialized behind one another) and no hashing of the multi-MB
/// source. A hit is decided by `==`, which is O(1) when the source is the very string
/// stored — the in-process schedules snapshot hands out the same instance for 30s — and
/// a length check plus memcmp otherwise, which is no more than reading it from Redis
/// cost. The strip on a miss runs outside the lock; two concurrent misses may both
/// strip, which is harmless.
final class StrippedMemo: @unchecked Sendable {
    /// Fixed routes (/schedules, /live, /all-live-games, /ws v1): a handful of keys.
    static let fixed = StrippedMemo(capacity: 16)
    /// `/schedules/date`, keyed by day.
    static let days = StrippedMemo(capacity: 8)

    private struct Entry {
        let source: String
        let value: String
    }

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [String: Entry] = [:]
    /// Insertion order, oldest first, for eviction.
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    func value(for key: String, source: String, build: (String) -> String) -> String {
        let hit = lock.withLock { entries[key] }
        if let hit, hit.source.utf8.count == source.utf8.count, hit.source == source {
            return hit.value
        }
        let built = build(source)
        lock.withLock {
            if entries.updateValue(Entry(source: source, value: built), forKey: key) == nil {
                order.append(key)
            }
            while order.count > capacity {
                entries[order.removeFirst()] = nil
            }
        }
        return built
    }
}

// MARK: - Per-game detail budget

/// When each college game's summary was last fetched, so a budget-limited tick goes to
/// the games that have waited longest. In memory only: a restart just resets the order.
actor CollegeFetchLedger {
    static let shared = CollegeFetchLedger()
    private var lastFetched: [String: Date] = [:]

    func snapshot() -> [String: Date] { lastFetched }

    func record(_ eventID: String, at date: Date = Date()) { lastFetched[eventID] = date }

    /// Drops games that are no longer on the board.
    func prune(keeping eventIDs: Set<String>) {
        lastFetched = lastFetched.filter { eventIDs.contains($0.key) }
    }
}

/// How the per-tick ESPN budget for college play-by-play / win probability / box scores
/// is spent. Live scores for every FBS game come from one scoreboard request a minute;
/// it's the per-game summary that scales with the slate — 41 college games were live at
/// once on rivalry week 2026. Only featured games are fetched proactively, at most
/// `fetchesPerTick` per tick, and the rest wait their turn (or are fetched on demand
/// when a user opens one — see `PlayResolver`).
enum CollegePBPPolicy {
    /// College summary fetches allowed per ESPNFetchJob tick (one a minute).
    static let fetchesPerTick = 12
    /// How long an on-demand college summary is served before it's refetched.
    static let onDemandFreshness: TimeInterval = 90

    /// Featured college games in the order the budget is spent: the Playoff, then
    /// ranked-vs-ranked, then one ranked team, then Power Four; within a tier, the game
    /// whose summary is oldest (never fetched first). Non-featured games are dropped.
    static func ordered(_ games: [Game], lastFetched: [String: Date]) -> [Game] {
        func tier(_ game: Game) -> Int {
            if game.isCollegeFootballPlayoff { return 0 }
            if game.homeSeed != nil && game.awaySeed != nil { return 1 }
            if game.hasRankedTeam { return 2 }
            return 3
        }
        return games
            .filter(\.isFeaturedCollegeGame)
            .enumerated()
            .sorted { lhs, rhs in
                let lt = tier(lhs.element), rt = tier(rhs.element)
                if lt != rt { return lt < rt }
                let ld = lhs.element.idEvent.flatMap { lastFetched[$0] } ?? .distantPast
                let rd = rhs.element.idEvent.flatMap { lastFetched[$0] } ?? .distantPast
                if ld != rd { return ld < rd }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Grants up to `limit` ESPN fetches down an already prioritised list, skipping the
    /// entries that don't need one (unchanged plays, archived finals cost nothing). The
    /// rest wait for a later tick. Deciding here, rather than as concurrent fetches
    /// reach a shared counter, is what keeps the order: a Power Four game whose checks
    /// finished first can't take the slot of a Playoff game still checking.
    static func grant<T>(_ ordered: [T], limit: Int, needsFetch: (T) -> Bool) -> (granted: [T], deferred: Int) {
        let needing = ordered.filter(needsFetch)
        return (Array(needing.prefix(limit)), max(0, needing.count - limit))
    }

    /// Whether a cached college summary is too old to serve for an in-progress game.
    /// Featured games are refreshed by the job; this is what keeps everything else
    /// current when someone actually opens it, at one ESPN fetch per game per 90s.
    static func isStale(_ cached: CachedPlays, isCollege: Bool, now: Date = Date()) -> Bool {
        isCollege && !cached.isFinal && now.timeIntervalSince(cached.fetchedAt) > onDemandFreshness
    }
}
