import Foundation

/// Which competitions each team plays in, keyed by `idTeam` (`/teams/competitions`).
/// Built by the server from the schedule, so following a team in onboarding can follow
/// its league and its cups too ("Arsenal" → Premier League, Champions League, FA Cup).
public struct TeamCompetitionIndex: Codable, Equatable, Sendable {
    /// `idTeam` → league ids (`Leagues.rawValue`), domestic cups included.
    public var teams: [String: [Int]]

    public init(teams: [String: [Int]]) {
        self.teams = teams
    }

    /// The team's known competitions, its own league(s) first, then cups and
    /// continental competitions, in the order the day page lists them.
    public func leagues(forTeam idTeam: String) -> [Leagues] {
        (teams[idTeam] ?? [])
            .compactMap(Leagues.init(rawValue:))
            .sorted { lhs, rhs in
                let l = lhs.isTeamCompetitionCup, r = rhs.isTeamCompetitionCup
                if l != r { return !l }
                return (lhs.competitionDisplayRank ?? .max) < (rhs.competitionDisplayRank ?? .max)
            }
    }
}

public extension Leagues {
    /// The national cup every club in this league enters. A cup a team hasn't
    /// reached yet isn't in the schedule (Premier League clubs join the FA Cup in
    /// January), so following a league's club follows its cup by this rule.
    var domesticCup: Leagues? {
        switch self {
        case .English_Premier_League, .English_League_Championship: return .FA_Cup
        case .La_Liga: return .Copa_del_Rey
        case .German_Bundesliga: return .DFB_Pokal
        case .Ligue_1: return .Coupe_De_France
        default: return nil
        }
    }

    /// Cups and continental or international tournaments, as opposed to a team's
    /// own league, for ordering a team's competitions.
    internal var isTeamCompetitionCup: Bool {
        switch self {
        case .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
             .UEFA_Champions_League, .UEFA_Europa_League, .UEFA_Conference_League,
             .UEFA_Nations_League, .FIFA_World_Cup, .Womens_World_Cup, .Copa_America:
            return true
        default:
            return false
        }
    }
}
