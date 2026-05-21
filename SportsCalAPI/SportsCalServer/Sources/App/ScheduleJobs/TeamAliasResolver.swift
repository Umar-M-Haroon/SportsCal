import Foundation
import Logging
import SportsCalModel

/// Resolves team-name variants (and curated short forms) to a stable canonical key
/// so the ESPN/TSDB merge can collapse duplicates like "PSG" and "Paris Saint-Germain"
/// onto one schedule entry.
///
/// Index sources, in build order:
/// 1. `Team.strTeam` — canonical TheSportsDB name
/// 2. each token in `Team.strAlternate` — TSDB-supplied + ESPN displayName merged in by ESPNTeamFetchJob
/// 3. small curated seed for short forms TSDB doesn't always carry (e.g. "PSG")
///
/// Built once per ESPNFetchJob tick from the cached `[Team]`; index size is small (~thousands).
struct TeamAliasResolver {

    enum CanonicalKey: Hashable {
        case id(String)
        case name(String)
    }

    private let nameToID: [String: String]
    private let idToCanonicalName: [String: String]

    init(teams: [Team], curatedAliases: [String: String] = TeamAliasResolver.curatedSeed, logger: Logger? = nil) {
        var nameToID: [String: String] = [:]
        var idToCanonicalName: [String: String] = [:]
        var canonicalNameToID: [String: String] = [:]

        for team in teams {
            guard let id = team.idTeam, !id.isEmpty,
                  let canonical = team.strTeam, !canonical.isEmpty else { continue }
            idToCanonicalName[id] = canonical
            canonicalNameToID[canonical] = id

            let canonicalKey = TeamAliasResolver.normalize(canonical)
            if nameToID[canonicalKey] == nil { nameToID[canonicalKey] = id }

            if let alternate = team.strAlternate {
                for alt in alternate.components(separatedBy: ", ") {
                    let trimmed = alt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let key = TeamAliasResolver.normalize(trimmed)
                    if nameToID[key] == nil { nameToID[key] = id }
                }
            }
        }

        var curatedSkipped: [String] = []
        for (alias, canonical) in curatedAliases {
            guard let id = canonicalNameToID[canonical] else {
                curatedSkipped.append("\(alias) -> \(canonical)")
                continue
            }
            let key = TeamAliasResolver.normalize(alias)
            if nameToID[key] == nil { nameToID[key] = id }
        }

        if !curatedSkipped.isEmpty {
            logger?.warning("TeamAliasResolver: curated entries skipped (canonical strTeam not in teams cache)", metadata: [
                "skipped": .array(curatedSkipped.map { .string($0) })
            ])
        }
        logger?.debug("TeamAliasResolver built", metadata: [
            "teamCount": "\(idToCanonicalName.count)",
            "aliasCount": "\(nameToID.count)",
            "curatedSkipped": "\(curatedSkipped.count)"
        ])

        self.nameToID = nameToID
        self.idToCanonicalName = idToCanonicalName
    }

    func canonicalKey(for name: String) -> CanonicalKey {
        let normalized = TeamAliasResolver.normalize(name)
        if let id = nameToID[normalized] {
            return .id(id)
        }
        return .name(normalized)
    }

    func canonicalName(forID id: String) -> String? {
        idToCanonicalName[id]
    }

    /// Stable key collapsing alias variants of the same fixture.
    /// Pair is sorted so home/away swap collapses; scoped by league so the same
    /// name pair across different leagues never collide.
    func dedupKey(home: String, away: String, leagueID: String?, day: String) -> String {
        let homeKey = canonicalKey(for: home)
        let awayKey = canonicalKey(for: away)
        let pair = [keyString(homeKey), keyString(awayKey)].sorted().joined(separator: "|")
        return "\(leagueID ?? "-")|\(pair)|\(day)"
    }

    private func keyString(_ key: CanonicalKey) -> String {
        switch key {
        case .id(let id): return "id:\(id)"
        case .name(let n): return "name:\(n)"
        }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased aliases → exact `strTeam` in TSDB. Resolved at construction;
    /// entries pointing to a strTeam not in the cache are logged and skipped.
    /// Grow from production logs surfaced by the alias-dedup warning path.
    static let curatedSeed: [String: String] = [
        "psg": "Paris Saint-Germain",
        "paris sg": "Paris Saint-Germain",
        "paris saint germain": "Paris Saint-Germain",
        "brighton": "Brighton & Hove Albion",
        "brighton hove albion": "Brighton & Hove Albion",
        "brighton and hove albion": "Brighton & Hove Albion",
        "bayern": "Bayern Munich",
        "bayern munchen": "Bayern Munich",
        "fc bayern": "Bayern Munich",
        "la clippers": "Los Angeles Clippers",
        "man utd": "Manchester United",
        "man city": "Manchester City",
        "spurs": "Tottenham Hotspur"
    ]
}
