//
//  WidgetAppIntents.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 2/15/26.
//

import AppIntents
import WidgetKit
import SportsCalModel

enum SportSelection: String, AppEnum {
    case allSports
    case basketball
    case soccer
    case hockey
    case mlb
    case nfl
    case golf
    case tennis
    case racing

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Sport"
    }

    static var caseDisplayRepresentations: [SportSelection: DisplayRepresentation] {
        [
            .allSports: "All Sports",
            .basketball: "Basketball",
            .soccer: "Soccer",
            .hockey: "Hockey",
            .mlb: "MLB",
            .nfl: "NFL",
            .golf: "Golf",
            .tennis: "Tennis",
            .racing: "Racing"
        ]
    }

    var sportType: SportType? {
        switch self {
        case .allSports: return nil
        case .basketball: return .basketball
        case .soccer: return .soccer
        case .hockey: return .hockey
        case .mlb: return .mlb
        case .nfl: return .nfl
        case .golf: return .golf
        case .tennis: return .tennis
        case .racing: return .racing
        }
    }

    static func from(sportType: SportType) -> SportSelection {
        switch sportType {
        case .basketball: return .basketball
        case .soccer: return .soccer
        case .hockey: return .hockey
        case .mlb: return .mlb
        case .nfl: return .nfl
        case .golf: return .golf
        case .tennis: return .tennis
        case .racing: return .racing
        }
    }
}

struct SportsWidgetIntent: WidgetConfigurationIntent, CustomIntentMigratedAppIntent {
    static let intentClassName = "ConfigurationIntent"

    static var title: LocalizedStringResource = "Sports Widget"
    static var description: IntentDescription = "Configure which sport to display"

    @Parameter(title: "Sport", default: .allSports)
    var sport: SportSelection

    @Parameter(title: "Leagues", default: [])
    var selectedLeagues: [LeagueSelection]

    @Parameter(title: "Favorites Only", default: false)
    var favoritesOnly: Bool

    static var parameterSummary: some ParameterSummary {
        When(\SportsWidgetIntent.$sport, .equalTo, .allSports) {
            Summary("Show \(\.$sport) games") {
                \.$selectedLeagues
                \.$favoritesOnly
            }
        } otherwise: {
            When(\SportsWidgetIntent.$sport, .equalTo, .soccer) {
                Summary("Show \(\.$sport) games") {
                    \.$selectedLeagues
                    \.$favoritesOnly
                }
            } otherwise: {
                When(\SportsWidgetIntent.$sport, .equalTo, .tennis) {
                    Summary("Show \(\.$sport) games") {
                        \.$selectedLeagues
                        \.$favoritesOnly
                    }
                } otherwise: {
                    Summary("Show \(\.$sport) games") {
                        \.$favoritesOnly
                    }
                }
            }
        }
    }
}

enum LeagueSelection: String, AppEnum {
    // Soccer
    case premierLeague
    case championship
    case bundesliga
    case serieA
    case ligue1
    case laLiga
    case eredivisie
    case mls
    case ligaMX
    case fifaWorldCup
    case championsLeague
    case europaLeague
    case faCup
    case copaDelRey
    case coupeDeFrance
    case dfbPokal
    case nationsLeague
    case copaAmerica
    case conferenceLeague
    case womensWorldCup
    // Tennis
    case atp
    case wta

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "League"
    }

    static var caseDisplayRepresentations: [LeagueSelection: DisplayRepresentation] {
        [
            .premierLeague: "Premier League",
            .championship: "English Championship",
            .bundesliga: "Bundesliga",
            .serieA: "Serie A",
            .ligue1: "Ligue 1",
            .laLiga: "La Liga",
            .eredivisie: "Eredivisie",
            .mls: "MLS",
            .ligaMX: "Liga MX",
            .fifaWorldCup: "FIFA World Cup",
            .championsLeague: "Champions League",
            .europaLeague: "Europa League",
            .faCup: "FA Cup",
            .copaDelRey: "Copa Del Rey",
            .coupeDeFrance: "Coupe De France",
            .dfbPokal: "DFB Pokal",
            .nationsLeague: "Nations League",
            .copaAmerica: "Copa America",
            .conferenceLeague: "Conference League",
            .womensWorldCup: "Women's World Cup",
            .atp: "ATP Tour",
            .wta: "WTA Tour",
        ]
    }

    var league: Leagues {
        switch self {
        case .premierLeague: return .English_Premier_League
        case .championship: return .English_League_Championship
        case .bundesliga: return .German_Bundesliga
        case .serieA: return .Serie_A
        case .ligue1: return .Ligue_1
        case .laLiga: return .La_Liga
        case .eredivisie: return .Eredivisie
        case .mls: return .MLS
        case .ligaMX: return .Liga_MX
        case .fifaWorldCup: return .FIFA_World_Cup
        case .championsLeague: return .UEFA_Champions_League
        case .europaLeague: return .UEFA_Europa_League
        case .faCup: return .FA_Cup
        case .copaDelRey: return .Copa_del_Rey
        case .coupeDeFrance: return .Coupe_De_France
        case .dfbPokal: return .DFB_Pokal
        case .nationsLeague: return .UEFA_Nations_League
        case .copaAmerica: return .Copa_America
        case .conferenceLeague: return .UEFA_Conference_League
        case .womensWorldCup: return .Womens_World_Cup
        case .atp: return .atp
        case .wta: return .wta
        }
    }

    /// The league name matching `Leagues.leagueName` / `Game.strLeague`
    var leagueName: String { league.leagueName }
}
