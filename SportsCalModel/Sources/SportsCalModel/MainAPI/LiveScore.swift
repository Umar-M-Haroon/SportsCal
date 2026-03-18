//
//  LiveScore.swift
//  
//
//  Created by Umar Haroon on 10/22/22.
//

import Foundation
public enum Leagues: Int, Codable, CaseIterable, Equatable {
    case English_Premier_League = 4328
    case English_League_Championship = 4329
    case German_Bundesliga = 4331
    case Serie_A = 4332
    case Ligue_1 = 4334
    case La_Liga = 4335
    case Eredivisie = 4337
    case MLS = 4346
    case Liga_MX = 4350
    case FIFA_World_Cup = 4429
    case UEFA_Champions_League = 4480
    case UEFA_Europa_League = 4481
    case FA_Cup = 4482
    case Copa_del_Rey = 4483
    case Coupe_De_France = 4484
    case DFB_Pokal = 4485
    case UEFA_Nations_League = 4490
    case Copa_America = 4499
    case UEFA_Conference_League = 5071
    case Womens_World_Cup = 4565
    
    case nfl = 4391
    case nba = 4387
    case nhl = 4380
    case mlb = 4424

    case pga = 4425
    case atp = 4464
    case wta = 4517

    case formula1 = 4370

    public var isSoccer: Bool {
        return ![Leagues.nfl, Leagues.nba, Leagues.nhl, Leagues.mlb, Leagues.pga, Leagues.atp, Leagues.wta, Leagues.formula1].contains(self)
    }

    public var isGolf: Bool {
        return self == .pga
    }

    public var isTennis: Bool {
        return [Leagues.atp, Leagues.wta].contains(self)
    }

    public var isRacing: Bool {
        return self == .formula1
    }
    
    public init?(slug: String) {
        switch slug {
        case "uefa.champions":
            self = .UEFA_Champions_League
        case "uefa.europa":
            self = .UEFA_Europa_League
        case "uefa.europa.conf":
            self = .UEFA_Conference_League
        case "eng.1":
            self = .English_Premier_League
        case "eng.fa":
            self = .FA_Cup
        case "esp.1":
            self = .La_Liga
        case "esp.copa_del_rey":
            self = .Copa_del_Rey
        case "ger.1":
            self = .German_Bundesliga
        case "usa.1":
            self = .MLS
        case "ita.1":
            self = .Serie_A
        case "fra.1":
            self = .Ligue_1
        case "fra.coupe_de_france":
            self = .Coupe_De_France
        case "eng.2":
            self = .English_League_Championship
        case "ned.1":
            self = .Eredivisie
        case "ger.dfb_pokal":
            self = .DFB_Pokal
        case "mex.1":
            self = .Liga_MX
        case "nba":
            self = .nba
        case "nhl":
            self = .nhl
        case "nfl":
            self = .nfl
        case "mlb":
            self = .mlb
        case "fifa.world":
            self = .FIFA_World_Cup
        case "uefa.nations":
            self = .UEFA_Nations_League
        case "conmebol.america":
            self = .Copa_America
        case "fifa.wwc":
            self = .Womens_World_Cup
        case "pga":
            self = .pga
        case "atp":
            self = .atp
        case "wta":
            self = .wta
        case "f1":
            self = .formula1
        default:
            return nil
        }
    }
    
    public var espnSlug: String? {
        switch self {
        case .UEFA_Champions_League:
            return "uefa.champions"
        case .UEFA_Europa_League:
            return "uefa.europa"
        case .UEFA_Conference_League:
            return "uefa.europa.conf"
        case .English_Premier_League:
            return "eng.1"
        case .FA_Cup:
            return "eng.fa"
        case .La_Liga:
            return "esp.1"
        case .Copa_del_Rey:
            return "esp.copa_del_rey"
        case .German_Bundesliga:
            return "ger.1"
        case .MLS:
            return "usa.1"
        case .Serie_A:
            return "ita.1"
        case .Ligue_1:
            return "fra.1"
        case .Coupe_De_France:
            return "fra.coupe_de_france"
        case .English_League_Championship:
            return "eng.2"
        case .Eredivisie:
            return "ned.1"
        case .DFB_Pokal:
            return "ger.dfb_pokal"
        case .Liga_MX:
            return "mex.1"
        case .nba:
            return "nba"
        case .nhl:
            return "nhl"
        case .nfl:
            return "nfl"
        case .mlb:
            return "mlb"
        case .FIFA_World_Cup:
            return "fifa.world"
        case .UEFA_Nations_League:
            return "uefa.nations"
        case .Copa_America:
            return "conmebol.america"
        case .Womens_World_Cup:
            return "fifa.wwc"
        case .pga:
            return "pga"
        case .atp:
            return "atp"
        case .wta:
            return "wta"
        case .formula1:
            return "f1"
        default:
            return nil
        }
    }
    
    public var leagueName: String {
        switch self {
        case .English_Premier_League:
            return "English Premier League"
        case .English_League_Championship:
            return "English Championship"
        case .German_Bundesliga:
            return "Bundesliga"
        case .Serie_A:
            return "Serie A"
        case .Ligue_1:
            return "Ligue 1"
        case .La_Liga:
            return "La Liga"
        case .Eredivisie:
            return "Eredivisie"
        case .MLS:
            return "MLS"
        case .Liga_MX:
            return "Liga MX"
        case .FIFA_World_Cup:
            return "FIFA World Cup"
        case .UEFA_Champions_League:
            return "UEFA Champions League"
        case .UEFA_Europa_League:
            return "UEFA Europa League"
        case .FA_Cup:
            return "FA Cup"
        case .Copa_del_Rey:
            return "Copa Del Rey"
        case .Coupe_De_France:
            return "Coupe De France"
        case .DFB_Pokal:
            return "DFB Pokal"
        case .UEFA_Nations_League:
            return "UEFA Nations League"
        case .Copa_America:
            return "Copa America"
        case .UEFA_Conference_League:
            return "UEFA Conference League"
        case .nfl:
            return "NFL"
        case .mlb:
            return "MLB"
        case .nhl:
            return "NHL"
        case .nba:
            return "NBA"
        case .Womens_World_Cup:
            return "FIFA Women's World Cup"
        case .pga:
            return "PGA Tour"
        case .atp:
            return "ATP Tour"
        case .wta:
            return "WTA Tour"
        case .formula1:
            return "Formula 1"
        }
    }

    public var sport: String {
        switch self {
        case .English_Premier_League, .English_League_Championship, .German_Bundesliga, .Serie_A, .Ligue_1, .La_Liga, .Eredivisie, .MLS, .Liga_MX, .FIFA_World_Cup, .UEFA_Champions_League, .UEFA_Europa_League, .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal, .UEFA_Nations_League, .Copa_America, .UEFA_Conference_League, .Womens_World_Cup:
            return "soccer"
        case .nfl:
            return "football"
        case .nba:
            return "basketball"
        case .nhl:
            return "hockey"
        case .mlb:
            return "baseball"
        case .pga:
            return "golf"
        case .atp, .wta:
            return "tennis"
        case .formula1:
            return "racing"
        }
    }

    /// Whether this league uses single-year season format (e.g., "2025") instead of "2024-2025"
    public var usesSingleYearSeason: Bool {
        switch self {
        case .atp, .wta, .pga, .formula1:
            return true
        default:
            return false
        }
    }
}
public struct LiveScore: Codable, Equatable {
    public init(nba: LiveEvent? = nil, mlb: LiveEvent? = nil, soccer: LiveEvent? = nil, nfl: LiveEvent? = nil, nhl: LiveEvent? = nil, golf: LiveEvent? = nil, tennis: LiveEvent? = nil, racing: LiveEvent? = nil, f1Standings: F1Standings? = nil) {
        self.nba = nba
        self.mlb = mlb
        self.soccer = soccer
        self.nfl = nfl
        self.nhl = nhl
        self.golf = golf
        self.tennis = tennis
        self.racing = racing
        self.f1Standings = f1Standings
    }

    public var nba: LiveEvent?
    public var mlb: LiveEvent?
    public var soccer: LiveEvent?
    public var nfl: LiveEvent?
    public var nhl: LiveEvent?
    public var golf: LiveEvent?
    public var tennis: LiveEvent?
    public var racing: LiveEvent?
    public var f1Standings: F1Standings?

    /// Merges two LiveScore objects, combining events per sport
    public func merging(with other: LiveScore?) -> LiveScore {
        guard let other else { return self }
        return LiveScore(
            nba: LiveEvent.merging(self.nba, other.nba),
            mlb: LiveEvent.merging(self.mlb, other.mlb),
            soccer: LiveEvent.merging(self.soccer, other.soccer),
            nfl: LiveEvent.merging(self.nfl, other.nfl),
            nhl: LiveEvent.merging(self.nhl, other.nhl),
            golf: LiveEvent.merging(self.golf, other.golf),
            tennis: LiveEvent.merging(self.tennis, other.tennis),
            racing: LiveEvent.merging(self.racing, other.racing),
            f1Standings: self.f1Standings ?? other.f1Standings
        )
    }

    mutating public func removeNonStarting() {
        nba?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        mlb?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        soccer?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        nfl?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        nhl?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        golf?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        tennis?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        racing?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
    }
    mutating public func removeOtherInfo() {
        soccer?.events.removeAll(where: { event in
            guard let idLeague = event.idLeague,
                  let leagueID = Int(idLeague) else { return true }
            return !Leagues.allCases.map({$0.rawValue}).contains(leagueID)
        })
        tennis?.events.removeAll(where: { event in
            guard let idLeague = event.idLeague,
                  let leagueID = Int(idLeague) else { return true }
            return !Leagues.allCases.map({$0.rawValue}).contains(leagueID)
        })
    }
}
