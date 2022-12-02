//
//  GameViewModel.swift
//  SportsCal
//
//  Created by Umar Haroon on 8/13/22.
//

import Foundation
import SwiftUI
import Combine
import SportsCalModel
#if canImport(ActivityKit)
import ActivityKit
#endif
@MainActor public class GameViewModel: NSObject, ObservableObject {
    init(appStorage: UserDefaultStorage, favorites: Favorites, totalGames: [Game]? = nil, filteredGames: [Game]? = nil, teamString: String? = "", favoriteGames: [Game]? = nil, sortedGames: Array<(key: DateComponents, value: Array<Game>)> = [], networkState: NetworkState = .loading) {
        self.appStorage = appStorage
        self.favorites = favorites
        self.totalGames = totalGames
        self.filteredGames = filteredGames
        self.teamString = teamString
        self.favoriteGames = favoriteGames
        self.sortedGames = sortedGames
        self.networkState = networkState
        self.gamesDict = [:]
        
        
        let folderURLs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        var gameFileURL = folderURLs[0]
        gameFileURL.appendPathComponent("games" + ".cache")
        var teamFileURL = folderURLs[0]
        teamFileURL.appendPathComponent("teams" + ".cache")
        do {
            let data = try JSONDecoder().decode(Cache<String, LiveScore>.self, from: Data(contentsOf: gameFileURL))
            gameCache = data
            let teamData = try JSONDecoder().decode(Cache<String, [Team]>.self, from: Data(contentsOf: teamFileURL))
            teamCache = teamData
        } catch let error {
            gameCache = Cache<String, LiveScore>()
            teamCache = Cache<String, [Team]>()
            print(error.localizedDescription)
        }
        super.init()
        getInfo()
    }
    
    var appStorage: UserDefaultStorage
    var favorites: Favorites
    var teams: [Team] = []
    @Published var totalGames: [Game]?
    @Published var filteredGames: [Game]?
    @Published var teamString: String? = ""
    @Published var favoriteGames: [Game]?
    @Published var sortedGames: Array<(key: DateComponents, value: Array<Game>)> = []
    @Published var networkState: NetworkState = .loading
    private var webSocketTask: URLSessionWebSocketTask?
    var restartTimer: Timer?
    var gamesDict: [SportType: [Game]]
    private var gameCache: Cache<String, LiveScore>?
    private var teamCache: Cache<String, [Team]>?
    private var liveCache: Cache<String, LiveScore>?
    @Published var currentLiveInfo: LiveScore?
    
    var liveEvents: [Game] {
        var games: [Game] = []
        if appStorage.shouldShowSoccer {
            var soccerGames = currentLiveInfo?.soccer?.events
            soccerGames = soccerGames?.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return !league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            games.append(contentsOf: soccerGames ?? [])
        }
        if appStorage.shouldShowMLB {
            var baseballGames = currentLiveInfo?.mlb?.events
            baseballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            games.append(contentsOf: currentLiveInfo?.mlb?.events ?? [])
        }
        if appStorage.shouldShowNBA {
            var basketballGames = currentLiveInfo?.nba?.events
            basketballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            games.append(contentsOf: basketballGames ?? [])
        }
        if appStorage.shouldShowNFL {
            var nflGames = currentLiveInfo?.nfl?.events
            nflGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            games.append(contentsOf: nflGames ?? [])
        }
        if appStorage.shouldShowNHL {
            var nhlGames = currentLiveInfo?.nhl?.events
            nhlGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            games.append(contentsOf: nhlGames ?? [])
        }
        return games
    }
    @objc
    private func getData() async {
        do {
            if let gameCache, let cacheGames = gameCache.value(for: "games") {
                setGames(result: cacheGames)
            }
            if let teamCache, let cacheTeams = teamCache.value(for: "teams") {
                self.teams = cacheTeams
            }
            let result = try await NetworkHandler.handleCall()
            self.teams = try await NetworkHandler.getTeams()
            self.currentLiveInfo = try await NetworkHandler.getLiveSnapshot()
            webSocketTask = nil
            webSocketTask = NetworkHandler.connectWebSocketForLive()
            webSocketTask?.resume()
            Task {
                try await receiveMessages()
            }
            setGames(result: result)
            gameCache?.insert(result, for: "games")
            teamCache?.insert(self.teams, for: "teams")
            try gameCache?.saveToDisk(with: "games")
            try teamCache?.saveToDisk(with: "teams")
            
            networkState = .loaded
            restartTimer = nil
        } catch let e {
            print(e)
            print(e.localizedDescription)
            networkState = .failed
            restartTimer = .init(timeInterval: 10, target: self, selector: #selector(getData), userInfo: nil, repeats: true)
        }
    }

    @objc
    func receiveMessages() async throws {
        if let webSocket = webSocketTask {
            let webSocketMessage = try await webSocket.receive()
            switch webSocketMessage {
            case .string(let jsonString):
                if let jsonData = jsonString.data(using: .utf8) {
                    let newLiveInfo = try JSONDecoder().decode(LiveScore.self, from: jsonData)
                    withAnimation {
                        if let currentLiveInfo = currentLiveInfo, currentLiveInfo != newLiveInfo {
                            self.currentLiveInfo = newLiveInfo
                        } else if currentLiveInfo == nil {
                            self.currentLiveInfo = newLiveInfo
                        }
                    }
                    #if canImport(ActivityKit)
                    if #available(iOS 16.1, *) {
                        Task { @MainActor in
                            try await updateLiveActivities()
                        }
                    }
                    #endif
                }
            case .data(_):
                break
            @unknown default:
                break
            }
            try await receiveMessages()
        }
    }
    
    func setGames(result: LiveScore) {
        totalGames = [result.nhl?.events, result.nfl?.events, result.soccer?.events, result.mlb?.events, result.nba?.events]
            .compactMap({$0})
            .flatMap({$0})
        filterSports(force: true)
    }
    func filterSports(searchString: String? = nil, force: Bool = false) {
//        print("⚠️ sports duration or selected sport changed, filtering")
//        print("⚠️ should show NFL \(appStorage.shouldShowNFL)")
//        print("⚠️ should show NBA \(appStorage.shouldShowNBA)")
//        print("⚠️ should show NHL \(appStorage.shouldShowNHL)")
//        print("⚠️ should show Soccer \(appStorage.shouldShowSoccer)")
//        print("⚠️ should show MLB \(appStorage.shouldShowMLB)")
        if force {
            totalGames = totalGames?.filter({ game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return false }
                return true
            }) ?? []
            gamesDict = Dictionary(grouping: totalGames ?? [], by: { game in
                SportType(league: Leagues.init(rawValue: Int(game.idLeague!)!)!)
            })
        }
        var allGames: [Game] = []
        if appStorage.shouldShowSoccer {
            allGames.append(contentsOf: gamesDict[.soccer] ?? [])
            allGames = allGames.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return !league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
        }
        if appStorage.shouldShowMLB {
            allGames.append(contentsOf: gamesDict[.mlb] ?? [])
        }
        if appStorage.shouldShowNBA {
            allGames.append(contentsOf: gamesDict[.basketball] ?? [])
        }
        if appStorage.shouldShowNFL {
            allGames.append(contentsOf: gamesDict[.nfl] ?? [])
        }
        if appStorage.shouldShowNHL {
            allGames.append(contentsOf: gamesDict[.hockey] ?? [])
        }
        filteredGames = allGames
            .filter({ game -> Bool in
                guard let date = game.getDate() else { return false }
                if appStorage.hidePastEvents {
                    //get the date components for the game and check it is greater than 0
                    return date.timeIntervalSinceNow > 0
                } else {
                    
                    var isValidForPastDuration: Bool = false
                    switch appStorage.hidePastGamesDuration {
                    case .oneWeek:
                        guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                        isValidForPastDuration = (days >= -7)
                    case .twoWeeks:
                        guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                        isValidForPastDuration = (days >= -14)
                    case .threeWeeks:
                        guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                        isValidForPastDuration = (days >= -21)
                    case .oneMonth:
                        guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                        isValidForPastDuration = (month <= -1)
                    case .twoMonths:
                        guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                        isValidForPastDuration = (month <= -2)
                    case .sixMonths:
                        guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                        isValidForPastDuration = (month <= -6)
                    case .oneYear:
                        guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                        isValidForPastDuration = (month <= -12)
                    case .oneDay:
                        guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                        isValidForPastDuration = (days >= -1)
                    }
                    return isValidForPastDuration
                }
            })
            .filter({ game -> Bool in
                // filter to show correct duration or if its in the past
                var isValidForFutureDuration: Bool = false
                guard let date = game.getDate() else { return false }

                switch appStorage.durations {
                case .oneWeek:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    isValidForFutureDuration = (days <= 7)
                case .twoWeeks:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    isValidForFutureDuration = (days <= 14)
                case .threeWeeks:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    isValidForFutureDuration = (days <= 21)
                case .oneMonth:
                    let components = Calendar.current.dateComponents([.month, .day], from: .now, to: date)
                    guard
                          let month = components.month else { return false }
                    isValidForFutureDuration = (month < 1)
                case .twoMonths:
                    guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    isValidForFutureDuration = (month < 2)
                case .sixMonths:
                    guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    isValidForFutureDuration = (month < 6)
                case .oneYear:
                    guard let month = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                    isValidForFutureDuration = (month < 12)
                case .oneDay:
                    guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                    isValidForFutureDuration = (days < 1)
                }
                return isValidForFutureDuration
                
            })
        print("⚠️ total amount of games, \(totalGames?.count) filtered result \(filteredGames?.count)")
        handleSearch(searchString: searchString)
        sortByDate()
        setFavorites()
    }
    func sortByDate() {
        let groupDic = Dictionary(grouping: filteredGames ?? []) { game -> DateComponents in
            let gameDate = game.getDate() ?? .now
            let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: gameDate)
            return date2
        }
        let sorted = groupDic.sorted(by: {
            if appStorage.soonestOnTop {
                return $0.key.date! < $1.key.date!
            }
            return $0.key.date! > $1.key.date!
        })
        var newDict: [DateComponents: [Game]] = [:]
        for sort in sorted {
            newDict[sort.key] = sort.value
        }
        sortedGames = sorted
    }
    
    func setFavorites() {
        favoriteGames = filteredGames?.filter({favorites.contains($0)})
    }
    
    func handleSearch(searchString: String?) {
        if let searchString, isValidSearchString(searchString: searchString) {
            filteredGames = filteredGames?
                .compactMap({$0})
                .filter({ game in
                    let homeTeam = Team.getTeamInfoFrom(teams: self.teams, teamID: game.idHomeTeam)
                    let awayTeam = Team.getTeamInfoFrom(teams: self.teams, teamID: game.idAwayTeam)
                    return (homeTeam?.strTeamShort ?? "").contains(searchString) ||
                    (homeTeam?.strTeam ?? "").contains(searchString) ||
                    (awayTeam?.strTeamShort ?? "").contains(searchString) ||
                    (awayTeam?.strTeam ?? "").contains(searchString)
                })
        }
    }
    func isValidSearchString(searchString: String) -> Bool {
        return !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func getInfo() {
        Task {
            await getData()
        }
    }
}

extension GameViewModel: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.webSocketTask = nil
           restartTimer = .init(timeInterval: 10, target: self, selector: #selector(receiveMessages), userInfo: nil, repeats: true)
    }
}
#if canImport(ActivityKit)
@available(iOS 16.1, *)
extension GameViewModel {
    func updateLiveActivities() async throws {
        var states: [String: LiveSportActivityAttributes.ContentState] = [:]
        for liveEvent in liveEvents {
            if let eventID = liveEvent.idEvent {
                let contentState = LiveSportActivityAttributes.ContentState(homeScore: Int(liveEvent.intHomeScore ?? "") ?? 0, awayScore: Int(liveEvent.intAwayScore ?? "") ?? 0, status: liveEvent.strStatus, progress: liveEvent.strProgress)
                states[eventID] = contentState
            }
        }
        for activity in Activity<LiveSportActivityAttributes>.activities {
            for await data in activity.pushTokenUpdates {
                let myToken = data.map { String(format: "%02x", $0)}.joined()
                try await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID)
            }
            let currentState = activity.contentState
            let currentAttributes = activity.attributes
            let eventID = currentAttributes.eventID
            if let savedContentState = states[eventID], savedContentState != currentState {
                await activity.update(using: savedContentState)
            }
        }
    }
}
#endif
