//
//  LiveFrame.swift
//  SportsCalModel
//
//  Envelope for the live-score WebSocket, so a tick that changes one score costs
//  one game on the wire instead of the whole multi-megabyte snapshot.
//

import Foundation

/// One push on the live WebSocket.
///
/// The unversioned protocol sent a bare `LiveScore` — every game in every sport —
/// whenever anything anywhere changed, uncompressed (WS frames bypass the edge's
/// gzip). At ~4.76 MB a frame that is paid per client per tick in server egress,
/// kernel socket memory, the user's cellular data, and a JSON decode on the phone.
///
/// A client that asks for this envelope (`/ws?frames=v2`) instead gets a `full`
/// frame on connect and `delta` frames after it, each carrying only the games whose
/// state actually moved. Clients that don't ask keep receiving the bare `LiveScore`,
/// so versions already in the field are unaffected.
public struct LiveFrame: Codable, Equatable {
    public enum Kind: String, Codable {
        /// `live` is the complete snapshot; replace local state with it.
        case full
        /// `live` holds only changed games; merge it into local state and drop `removed`.
        case delta
    }

    /// Monotonic per-process sequence number. A client echoes nothing back — it is
    /// carried so the server can tell whether the client is exactly one frame behind
    /// (and can take a delta) or further adrift (and needs a fresh `full`).
    public var seq: Int
    public var kind: Kind
    public var live: LiveScore
    /// Event IDs that left the snapshot since the previous sequence — games that went
    /// final and were pruned. Only meaningful on a `delta`.
    public var removed: [String]?

    public init(seq: Int, kind: Kind, live: LiveScore, removed: [String]? = nil) {
        self.seq = seq
        self.kind = kind
        self.live = live
        self.removed = removed
    }
}

public extension LiveScore {
    /// The eight per-sport buckets, paired with the sport they belong to, so callers
    /// can iterate them without restating the list (and forgetting one when a sport
    /// is added — the compiler checks `SportType.allCases` here, not a literal).
    static var sportKeyPaths: [(SportType, WritableKeyPath<LiveScore, LiveEvent?>)] {
        [
            (.basketball, \.nba),
            (.mlb,        \.mlb),
            (.soccer,     \.soccer),
            (.nfl,        \.nfl),
            (.hockey,     \.nhl),
            (.golf,       \.golf),
            (.tennis,     \.tennis),
            (.racing,     \.racing),
        ]
    }

    /// Every game in the snapshot, tagged with its bucket.
    var allGamesBySport: [(sport: SportType, games: [Game])] {
        Self.sportKeyPaths.compactMap { sport, keyPath in
            guard let event = self[keyPath: keyPath] else { return nil }
            return (sport, event.events)
        }
    }

    /// Returns a copy with `delta`'s games merged in by event ID and `removed` dropped.
    ///
    /// A game in `delta` replaces the game with the same `idEvent` in the receiver, or
    /// is appended when it's new. Games without an `idEvent` can't be addressed
    /// individually, so the server never puts them in a delta — they only ever arrive
    /// in a `full` frame, and a merge leaves the receiver's copies alone.
    ///
    /// Enrichment (`f1Standings`, `worldCup`) is carried only when it changed; absent
    /// means "unchanged", not "cleared".
    func applying(delta: LiveScore, removed: [String]?) -> LiveScore {
        var result = self
        let removedIDs = Set(removed ?? [])

        for (_, keyPath) in Self.sportKeyPaths {
            let incoming = delta[keyPath: keyPath]?.events ?? []
            let existing = result[keyPath: keyPath]?.events ?? []
            guard !incoming.isEmpty || !removedIDs.isEmpty else { continue }

            var merged = existing
            var indexByID: [String: Int] = [:]
            for (index, game) in merged.enumerated() {
                if let id = game.idEvent { indexByID[id] = index }
            }

            for game in incoming {
                guard let id = game.idEvent else { continue }
                if let index = indexByID[id] {
                    merged[index] = game
                } else {
                    indexByID[id] = merged.count
                    merged.append(game)
                }
            }

            if !removedIDs.isEmpty {
                merged.removeAll { game in
                    guard let id = game.idEvent else { return false }
                    return removedIDs.contains(id)
                }
            }

            // Don't materialize an empty bucket that wasn't there before — a nil
            // bucket and an empty one read differently downstream.
            if merged.isEmpty && result[keyPath: keyPath] == nil { continue }
            result[keyPath: keyPath] = LiveEvent(events: merged)
        }

        if let standings = delta.f1Standings { result.f1Standings = standings }
        if let worldCup = delta.worldCup { result.worldCup = worldCup }
        return result
    }

    /// Cheap stand-in for `==` on a whole snapshot.
    ///
    /// `LiveScore`'s synthesized `Equatable` bottoms out in `Game`'s, which walks ~45
    /// stored properties per game including several arrays. The live socket compared two
    /// snapshots that way on the main actor once per tick. Hashing each game's volatile
    /// fields instead answers the only question the caller actually has — "did anything
    /// I display change?" — without the deep walk.
    ///
    /// Not a substitute for equality in general: distinct snapshots can collide, and it
    /// ignores fields no live view reads. Use it to decide whether to republish state,
    /// not to decide whether two snapshots are the same.
    var contentSignature: Int {
        var hasher = Hasher()
        for (_, keyPath) in Self.sportKeyPaths {
            guard let events = self[keyPath: keyPath]?.events else {
                hasher.combine(-1)
                continue
            }
            hasher.combine(events.count)
            for game in events {
                hasher.combine(game.idEvent)
                hasher.combine(Self.liveSignature(of: game))
            }
        }
        hasher.combine(f1Standings)
        hasher.combine(worldCup)
        return hasher.finalize()
    }

    /// Compact signature of the fields that make a live game "changed" for display
    /// purposes. Deliberately not full equality: `Game`'s synthesized `==` walks ~45
    /// fields including several arrays, and the enrichment among them churns without
    /// changing anything a viewer sees.
    static func liveSignature(of game: Game) -> Int {
        var hasher = Hasher()
        hasher.combine(game.intHomeScore)
        hasher.combine(game.intAwayScore)
        hasher.combine(game.strStatus)
        hasher.combine(game.strProgress)
        hasher.combine(game.lastPlay)
        hasher.combine(game.isCompleted)
        hasher.combine(game.homeLinescores)
        hasher.combine(game.awayLinescores)
        hasher.combine(game.leaderboardEntries)
        hasher.combine(game.raceTiming)
        return hasher.finalize()
    }
}
