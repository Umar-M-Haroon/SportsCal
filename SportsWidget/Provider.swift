//
//  Provider.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/30/22.
//

import Foundation
import WidgetKit
import SwiftUI
import Intents
import Combine
import SportsCalModel

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
    let game: [Game]?
    var images: [String: Data]?
    let teams: [Team]
}
class Provider: IntentTimelineProvider {
    let sampleGames: [Game] = [
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134876", idAwayTeam: "134881", strHomeTeam: "Milwaukee Bucks", strAwayTeam: "Denver Nuggets", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134877", idAwayTeam: "134882", strHomeTeam: "Golden State Warriors", strAwayTeam: "Boston Celtics", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134878", idAwayTeam: "134883", strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Houston Rockets", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134879", idAwayTeam: "134884", strHomeTeam: "Seattle Supersonics", strAwayTeam: "Washington Wizards", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134874", idAwayTeam: "134885", strHomeTeam: "Detroit Pistons", strAwayTeam: "Portland Trailblazers", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00")
    ]
    
    let images: [String: Data] = ["134875": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134880": UIImage(systemName: "basketball.circle")!.pngData()!,
                                  "134876": UIImage(systemName: "basketball.circle")!.pngData()!, "134881": UIImage(systemName: "basketball.circle.fill")!.pngData()!,
                                  "134877": UIImage(systemName: "basketball")!.pngData()!, "134882": UIImage(systemName: "basketball.fill")!.pngData()!,
                                  "134878": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134883": UIImage(systemName: "basketball")!.pngData()!,
                                  "134879": UIImage(systemName: "basketball.fill")!.pngData()!, "134884": UIImage(systemName: "basketball.circle")!.pngData()!,
                                  "134874": UIImage(systemName: "basketball.circle.fill")!.pngData()!, "134885": UIImage(systemName: "basketball.fill")!.pngData()!]
    
    let teams: [Team] = [
        Team.init(idTeam: "134875", strTeam: "Dallas Mavericks", strTeamShort: "DAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134876", strTeam: "Milwaukee Bucks", strTeamShort: "MIL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134877", strTeam: "Golden State Warriors", strTeamShort: "GSW", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134878", strTeam: "Los Angeles Lakers", strTeamShort: "LAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134879", strTeam: "Seattle Supersonics", strTeamShort: "SEA", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134874", strTeam: "Detroit Pistons", strTeamShort: "DET", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134880", strTeam: "Utah Jazz", strTeamShort: "UTA", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134881", strTeam: "Denver Nuggets", strTeamShort: "DEN", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134882", strTeam: "Boston Celtics", strTeamShort: "BOS", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134883", strTeam: "Houston Rockets", strTeamShort: "HOU", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134884", strTeam: "Washington Wizards", strTeamShort: "WAS", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134875", strTeam: "Portland Trailblazers", strTeamShort: "POR", strAlternate: nil, strTeamBadge: nil),
    ]
    
    func placeholder(in context: Context) -> SimpleEntry {
        let entry = SimpleEntry(date: Date(), configuration: .init(), game: sampleGames, images: images, teams: teams)
        return entry
    }
    
    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), configuration: configuration, game: sampleGames, images: images, teams: teams)
        completion(entry)
    }
    
    func getImagesFor(homeTeam: Team, awayTeam: Team) async throws -> [String: Data] {
        guard let homeImageURL = homeTeam.strTeamBadge,
              let homeID = homeTeam.idTeam,
              let awayImageURL = awayTeam.strTeamBadge,
              let awayID = awayTeam.idTeam else {
            return [:]
        }
        async let homeImage = NetworkHandler.getImageFor(url: homeImageURL, size: .tiny)
        async let awayImage = NetworkHandler.getImageFor(url: awayImageURL, size: .tiny)
        return [homeID: try await homeImage, awayID: try await awayImage]
    }
    
    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        Task { @MainActor in
            await completion(timelineHandler(configuration: configuration))
        }
    }
    
    func timelineHandler(configuration: ConfigurationIntent) async -> Timeline<Entry> {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        var (games, teams) = await handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration))
        if let league = configuration.SoccerLeague, configuration.GameType == .soccer, league != "All Leagues" {
            games = games.filter({ Leagues(rawValue: Int($0.idLeague ?? "") ?? 0)?.leagueName == league })
        }
        let entryDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)
        if games.isEmpty {
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [], images: nil, teams: teams)
            entries.append(entry)
        } else if games.count < 2, let game = games.first {
            var entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [game], images: nil, teams: teams)
            guard let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam),
                  let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) else {
                entries.append(entry)
                return Timeline(entries: entries, policy: .atEnd)
            }
            if let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                entry.images = images
            }
            entries.append(entry)
        } else {
            var allImages: [String: Data] = [:]
            for game in games.prefix(upTo: min(games.count, 7)) {
                if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) {
                    async let images = getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam)
                    try? await allImages.merge(images, uniquingKeysWith: {$1})
                }
            }
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: games.sorted(by: {$0.isoDate ?? .now < $1.isoDate ?? .now}), images: allImages, teams: teams)
            entries.append(entry)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
    
    func configurationToString(configuration: ConfigurationIntent) -> SportType {
        switch configuration.GameType {
        case .mLB:
            return .mlb
        case .nBA:
            return .basketball
        case .nHL:
            return .hockey
        case .nFL:
            return .nfl
        case .soccer:
            return .soccer
        case .unknown:
            return .hockey
        }
    }
    
    
    func handleNetworking(favoriteOnly: Bool, type: SportType) async -> ([Game], [Team])  {
        do {
            var games = try await NetworkHandler.getScheduleFor(sport: type).events
            games = games
                .filter({ game -> Bool in
                    guard let date = game.isoDate else { return false }
                    return date.timeIntervalSinceNow > 0
                })
            async let teams = NetworkHandler.getTeams()
            
            let favorites = Favorites()
            if favoriteOnly {
                var favGames = games
                favGames.removeAll { game in
                    !favorites.contains(game)
                }
                if !favGames.isEmpty {
                    return await (favGames, try teams)
                }
            }
            return await (games, try teams)
        } catch let e {
            return ([Game(idLeague: "4387", strHomeTeam: "g", strAwayTeam: e.localizedDescription)], [])
        }
    }
}
