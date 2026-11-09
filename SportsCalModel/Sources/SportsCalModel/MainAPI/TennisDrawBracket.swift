//
//  TennisDrawBracket.swift
//  SportsCalModel
//
//  A tournament's singles draw laid out as a bracket, from the matches the app holds.
//
//  ESPN sends no draw positions: a round's matches arrive in order of play, and their ids
//  aren't in draw order either. The bracket is rebuilt from who played whom instead. The
//  last round present is taken as it comes; each earlier round is ordered by the matches
//  that fed it (the earlier match containing a player from the later one). So the top half
//  of every column lines up with the column after it.
//
//  Matches that feed nothing yet (the next round isn't drawn) go below the linked ones, and
//  every column is padded so each slot has exactly two feeders in the column before. The
//  app keeps about a month of tennis, so a current tournament's early rounds are normally
//  all there. When they aren't, the bracket is simply partial.
//

import Foundation

public struct TennisDrawBracket {
    public struct Round: Identifiable {
        /// ESPN's round name: "Round 1", "Quarterfinal".
        public let name: String
        /// "R1", "QF", for the round picker.
        public let shortLabel: String
        /// The round's matches in draw order. Nil is an empty slot: a bye, a match not
        /// drawn yet, or one the app no longer holds.
        public let slots: [Game?]

        public var id: String { name }
    }

    /// Knockout rounds, first to last. Qualifying and round-robin groups are left out.
    public let rounds: [Round]

    /// Builds the bracket from one draw's matches (see ``singles(_:tour:)``).
    ///
    /// - Parameter games: The singles matches of one draw, in any order.
    public init(games: [Game]) {
        var seen = Set<String>()
        var byRank: [Int: [Game]] = [:]
        var names: [Int: String] = [:]
        for game in games {
            guard seen.insert(game.id).inserted,
                  let name = game.round, let rank = Self.rank(ofRound: name) else { continue }
            byRank[rank, default: []].append(game)
            names[rank] = name
        }
        let ranks = byRank.keys.sorted()
        guard let lastRank = ranks.last else {
            rounds = []
            return
        }

        // Last round as it comes (by start time); each earlier one ordered by what it fed.
        var columns: [[Game?]] = Array(repeating: [], count: ranks.count)
        columns[ranks.count - 1] = (byRank[lastRank] ?? []).sorted(by: Self.playOrder)
        for index in stride(from: ranks.count - 2, through: 0, by: -1) {
            let matches = byRank[ranks[index]] ?? []
            var byPlayer: [String: Game] = [:]
            for match in matches {
                for id in Self.participantIDs(match) { byPlayer[id] = match }
            }
            var placed = Set<String>()
            var column: [Game?] = []
            column.reserveCapacity(columns[index + 1].count * 2)
            for slot in columns[index + 1] {
                for id in [slot?.idHomeTeam, slot?.idAwayTeam] {
                    let feeder = id.flatMap { Self.isRealParticipant($0) ? byPlayer[$0] : nil }
                    if let feeder, placed.insert(feeder.id).inserted {
                        column.append(feeder)
                    } else {
                        column.append(nil)
                    }
                }
            }
            column += matches.filter { !placed.contains($0.id) }.sorted(by: Self.playOrder).map { Optional($0) }
            columns[index] = column
        }

        // Pad from the end so slot i of each column is fed by slots 2i and 2i+1 before it.
        let last = ranks.count - 1
        var width = 1
        for index in 0...last {
            let span = 1 << (last - index)
            width = Swift.max(width, (columns[index].count + span - 1) / span)
        }
        rounds = ranks.indices.map { index in
            let size = width << (last - index)
            var slots = columns[index]
            if slots.count < size { slots += Array(repeating: nil, count: size - slots.count) }
            let name = names[ranks[index]] ?? ""
            return Round(name: name, shortLabel: Self.shortLabel(ofRound: name), slots: slots)
        }
    }

    /// Whether the empty slot `slot` of round `round` is a bye: the first round, where the
    /// player it would have fed is already in the next one.
    ///
    /// - Parameters:
    ///   - round: The index into ``rounds``.
    ///   - slot: The index into that round's slots.
    public func isBye(round: Int, slot: Int) -> Bool {
        guard round == 0, rounds.count > 1, slot < rounds[0].slots.count, rounds[0].slots[slot] == nil else { return false }
        let parentSlots = rounds[1].slots
        guard slot / 2 < parentSlots.count, let parent = parentSlots[slot / 2] else { return false }
        let id = slot % 2 == 0 ? parent.idHomeTeam : parent.idAwayTeam
        return id.map(Self.isRealParticipant) ?? false
    }

    /// The singles matches of `tour`'s draw (both tours' when nil), qualifying included
    /// (the bracket drops it).
    ///
    /// - Parameters:
    ///   - games: Any tennis games; non-matches and doubles are dropped.
    ///   - tour: ATP or WTA, or nil for a single-tour event.
    public static func singles(_ games: [Game], tour: Leagues?) -> [Game] {
        games.filter { game in
            game.isTennisMatch && !game.isTennisDoubles
                && (tour.map { game.belongsToTennisTour($0) } ?? true)
        }
    }

    // MARK: Rounds

    /// Column order for a knockout round; nil for qualifying, groups and anything unnamed.
    ///
    /// - Parameter name: ESPN's round name.
    static func rank(ofRound name: String) -> Int? {
        let lower = name.lowercased()
        if lower.contains("qualif") || lower.contains("group") || lower.contains("robin") { return nil }
        if lower.contains("semifinal") { return 101 }
        if lower.contains("quarterfinal") { return 100 }
        if lower == "final" || lower.hasSuffix(" final") { return 102 }
        // "Round of 16" → before the quarterfinals, however many rounds came first.
        if lower.hasPrefix("round of "), let size = Int(lower.dropFirst("round of ".count)), size > 8 {
            return 100 - Int(log2(Double(size))) + 2
        }
        // "Round 1", "1st Round", "Round 4".
        if let number = lower.split(separator: " ").lazy.compactMap({ Int($0.filter(\.isNumber)) }).first,
           (1...10).contains(number) {
            return number
        }
        return nil
    }

    /// "R1", "R16", "QF", "SF", "F"; other names as they are.
    ///
    /// - Parameter name: ESPN's round name.
    public static func shortLabel(ofRound name: String) -> String {
        switch rank(ofRound: name) {
        case 102?: return "F"
        case 101?: return "SF"
        case 100?: return "QF"
        case let rank? where rank < 50: return "R\(rank)"
        default:
            if name.lowercased().hasPrefix("round of "), let size = name.split(separator: " ").last {
                return "R\(size)"
            }
            return name
        }
    }

    // MARK: Helpers

    /// ESPN fills undrawn slots with "TBD" and placeholder athlete ids (-3, -4).
    static func isRealParticipant(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix("-") && id != "0"
    }

    private static func participantIDs(_ game: Game) -> [String] {
        var ids: [String] = []
        if let home = game.idHomeTeam, isRealParticipant(home), game.strHomeTeam != "TBD" { ids.append(home) }
        if let away = game.idAwayTeam, isRealParticipant(away), game.strAwayTeam != "TBD" { ids.append(away) }
        return ids
    }

    private static func playOrder(_ lhs: Game, _ rhs: Game) -> Bool {
        if lhs.sortTimestamp != rhs.sortTimestamp { return lhs.sortTimestamp < rhs.sortTimestamp }
        return lhs.id < rhs.id
    }
}
