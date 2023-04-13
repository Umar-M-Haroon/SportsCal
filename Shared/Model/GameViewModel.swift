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
import OrderedCollections
#if canImport(ActivityKit)
import ActivityKit
#endif
@MainActor public class GameViewModel: NSObject, ObservableObject {
    
    @Published var appStorage: UserDefaultStorage
    @Published var totalGames: [Game]?
    @Published var filteredGames: [Game]?
    @Published var teamString: String? = ""
    @Published var favoriteGames: [Game]?
    @Published var sortedGames: Array<(key: DateComponents, value: Array<Game>)> = []
    @Published var networkState: NetworkState = .loading
    @Published var currentLiveInfo: LiveScore?
    var currentlyLiveSports: [SportType] = []

    var favorites: Favorites
    var teams: [Team] = []
    var teamsDict: [String? : [Team]] = [:]
    var teamsDictName: [String? : [Team]] = [:]
    var restartTimer: Timer?
    var gamesDict: [SportType: [Game]] = [:]
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var gameCache: Cache<String, LiveScore>?
    private var teamCache: Cache<String, [Team]>?
    private var liveCache: Cache<String, LiveScore>?
    private var cancellables: Set<AnyCancellable> = []
    private var networkFetchTask: Task<Void, Never>?
    
    var liveEvents: [Game] {
        var games: [Game] = []
        if appStorage.shouldShowSoccer {
            var soccerGames = currentLiveInfo?.soccer?.events
            soccerGames = soccerGames?.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
            if let soccerGames {
                games.append(contentsOf: soccerGames)
                if !games.isEmpty {
                    currentlyLiveSports.append(.soccer)
                }
            }
        }
        if appStorage.shouldShowMLB {
            var baseballGames = currentLiveInfo?.mlb?.events
            baseballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let baseballGames {
                games.append(contentsOf: baseballGames)
                if !games.isEmpty {
                    currentlyLiveSports.append(.mlb)
                }
            }
        }
        if appStorage.shouldShowNBA {
            var basketballGames = currentLiveInfo?.nba?.events
            basketballGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else {
                    return true
                }
                return false
            })
            if let basketballGames {
                games.append(contentsOf: basketballGames)
                if !games.isEmpty {
                    currentlyLiveSports.append(.basketball)
                }
            }
        }
        if appStorage.shouldShowNFL {
            var nflGames = currentLiveInfo?.nfl?.events
            nflGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })
            if let nflGames {
                games.append(contentsOf: nflGames)
                if !games.isEmpty {
                    currentlyLiveSports.append(.nfl)
                }
            }
        }
        if appStorage.shouldShowNHL {
            var nhlGames = currentLiveInfo?.nhl?.events
            nhlGames?.removeAll(where: { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let _ = Leagues(rawValue: intLeague) else { return true }
                return false
            })

            if let nhlGames {
                games.append(contentsOf: nhlGames)
                if !games.isEmpty {
                    currentlyLiveSports.append(.hockey)
                }
            }
        }
        return Array(OrderedSet(games))
    }
    
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
            liveCache = Cache<String, LiveScore>(entryLifetime: 15 * 60)
            print(error.localizedDescription)
        }
        super.init()
        if let cacheGames = gameCache?.value(for: "games") {
            setGames(result: cacheGames)
        }
        if let cacheTeams = teamCache?.value(for: "teams") {
            self.teams = cacheTeams
            var teamsDict = Dictionary(grouping: self.teams, by: \.idTeam)
            teamsDict = teamsDict.mapValues { teams in
                return Array(Set(teams))
            }
            self.teamsDict = teamsDict
            var teamsDictName = Dictionary(grouping: self.teams, by: \.strTeam)
            teamsDictName = teamsDict.mapValues { teams in
                return Array(Set(teams))
            }
            self.teamsDictName = teamsDictName
        }
        if let liveInfo = liveCache?.value(for: "live") {
            self.currentLiveInfo = liveInfo
        }
        getInfo()
        appStorage.objectWillChange
            .debounce(for: 1, scheduler: RunLoop.main)
            .sink {
                withAnimation {
                    self.networkState = .loading
                    
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleLiveGames() async throws {
        print("🛜getting Live Games")
        async let liveInfo = NetworkHandler.getLiveSnapshot(debug: appStorage.debugMode)
        self.currentLiveInfo = try await liveInfo
        if let liveInfo = currentLiveInfo {
            liveCache?.insert(liveInfo, for: "live")
        }
        try liveCache?.saveToDisk(with: "live")
    }
    
    private func handleTeams() async throws {
        print("🛜getting teams")
        async let teams = NetworkHandler.getTeams(debug: appStorage.debugMode)
        self.teams = try await teams
        self.teamsDict = Dictionary(grouping: self.teams, by: \.idTeam)
        var teamsDictName = Dictionary(grouping: self.teams, by: \.strTeam)
        teamsDictName = teamsDict.mapValues { teams in
            return Array(Set(teams))
        }
        teamCache?.insert(self.teams, for: "teams")
        try teamCache?.saveToDisk(with: "teams")
        self.teamsDictName = teamsDictName
    }
    
    private func handleLiveWebsocket() {
        webSocketTask = nil
        webSocketTask = NetworkHandler.connectWebSocketForLive(debug: appStorage.debugMode)
        webSocketTask?.resume()
        Task {
            try await receiveMessages()
        }
    }
    
    func shouldAddTask(sport: SportType) -> Bool {
        switch sport {
        case .basketball:
            return appStorage.shouldShowNBA
        case .soccer:
            return appStorage.shouldShowSoccer
        case .hockey:
            return appStorage.shouldShowNHL
        case .mlb:
            return appStorage.shouldShowMLB
        case .nfl:
            return appStorage.shouldShowNFL
        }
    }
    
    fileprivate func handleGames() async throws {
        let groupResult = try await withThrowingTaskGroup(of: [SportType: LiveEvent].self) { group in
            var events: [SportType: LiveEvent] = [:]
            for sport in SportType.allCases {
                if shouldAddTask(sport: sport) {
                    print("🛜adding task and requesting \(sport)")
                    group.addTask {
                        return [sport: try await NetworkHandler.getScheduleFor(sport: sport, debug: self.appStorage.debugMode)]
                    }
                }
            }
            for try await schedule in group {
                events.merge(schedule) { liveEvent1, liveEvent2 in
                    liveEvent2
                }
            }
            return LiveScore(nba: events[.basketball], mlb: events[.mlb], soccer: events[.soccer], nfl: events[.nfl], nhl: events[.hockey])
        }
        
        gameCache?.insert(groupResult, for: "games")
        try gameCache?.saveToDisk(with: "games")
        setGames(result: groupResult)
    }
    
    @objc
    private func getData() async {
        do {
            try await withThrowingTaskGroup(of: Void.self, body: { group in
                group.addTask {
                    try await self.handleTeams()
                }
                group.addTask {
                    try await self.handleLiveGames()
                }
                group.addTask {
                    try await self.handleGames()
                }
                try await group.waitForAll()
            })
            handleLiveWebsocket()
            networkState = .loaded
            networkFetchTask = nil
        } catch let e {
            print(e)
            print(e.localizedDescription)
            networkState = .failed
            restartTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { [weak self] _ in
                self?.getInfo()
            })
        }
    }

    @objc
    func receiveMessages() async throws {
        if let webSocket = webSocketTask {
            let webSocketMessage = try await webSocket.receive()
            switch webSocketMessage {
            case .string(let jsonString):
                if let jsonData = jsonString.data(using: .utf8) {
                    var newLiveInfo = try JSONDecoder().decode(LiveScore.self, from: jsonData)
                    newLiveInfo.removeNonStarting()
                    newLiveInfo.removeOtherInfo()
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
    
    func handleSports(force: Bool = false) {
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
    }
    
    func getGamesFromUserPreferences() -> [Game] {
        var allGames: [Game] = []
        if appStorage.shouldShowSoccer {
            allGames.append(contentsOf: gamesDict[.soccer] ?? [])
            allGames = allGames.filter { game in
                guard let leagueString = game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { return false }
                return league.isSoccer && !appStorage.hiddenCompetitions.contains(where: {$0 == league.leagueName})
            }
        }
        if appStorage.shouldShowMLB {
            allGames.append(contentsOf: gamesDict[.mlb] ?? [])
        }
        if appStorage.shouldShowNBA {
            if let basketballGames = gamesDict[.basketball] {
                allGames.append(contentsOf: basketballGames)
            }
        }
        if appStorage.shouldShowNFL {
            allGames.append(contentsOf: gamesDict[.nfl] ?? [])
        }
        if appStorage.shouldShowNHL {
            allGames.append(contentsOf: gamesDict[.hockey] ?? [])
        }
        return allGames
    }
    
    func isValidInPast(game: Game) -> Bool {
        guard let date = game.standardDate else { return true }
        var isValidForPastDuration: Bool = false
        if self.appStorage.hidePastEvents {
            return date.timeIntervalSinceNow > 0
        } else {
            switch self.appStorage.hidePastGamesDuration {
            case .oneWeek:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days <= 7)
            case .twoWeeks:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -14)
            case .threeWeeks:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -21)
            case .oneMonth:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 <= -1)
            case .twoMonths:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 <= -2)
            case .sixMonths:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 <= -6)
            case .oneYear:
                guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
                isValidForPastDuration = (month1 <= -12)
            case .oneDay:
                guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
                isValidForPastDuration = (days >= -1)
            }
        }
        return isValidForPastDuration
    }
    
    func isValidInFuture(game: Game) -> Bool {
        guard let date = game.standardDate else { return true }
        var isValidForFutureDuration: Bool = false
        switch self.appStorage.durations {
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
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 1)
        case .twoMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 2)
        case .sixMonths:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 2)
        case .oneYear:
            guard let month1 = Calendar.current.dateComponents([.month], from: .now, to: date).month else { return false }
            isValidForFutureDuration = (month1 < 12)
        case .oneDay:
            guard let days = Calendar.current.dateComponents([.day], from: .now, to: date).day else { return false }
            isValidForFutureDuration = (days < 1)
        }
        return isValidForFutureDuration
    }
    
    func filterAndSortGamesFromUserPreferences(games: [Game]) -> [Game] {
        return games.filter({ game -> Bool in
            return isValidInPast(game: game) && isValidInFuture(game: game)
        })
        .sorted { lhs, rhs in
            lhs.standardDate ?? .now < rhs.standardDate ?? .now
        }
    }
    
    func filterSports(searchString: String? = nil, force: Bool = false) {
        #if DEBUG
        print("⚠️ sports duration or selected sport changed, filtering")
        print("⚠️ should show NFL \(appStorage.shouldShowNFL)")
        print("⚠️ should show NBA \(appStorage.shouldShowNBA)")
        print("⚠️ should show NHL \(appStorage.shouldShowNHL)")
        print("⚠️ should show Soccer \(appStorage.shouldShowSoccer)")
        print("⚠️ should show MLB \(appStorage.shouldShowMLB)")
        #endif
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
        filteredGames = filterAndSortGamesFromUserPreferences(games: getGamesFromUserPreferences())

        print("⚠️ total amount of games, \(totalGames?.count ?? 0) filtered result \(filteredGames?.count ?? 0)")
        handleSearch(searchString: searchString)
        sortByDate()
        setFavorites()
    }
    func sortByDate() {
        let groupDic = Dictionary(grouping: filteredGames ?? []) { game -> DateComponents in
            let gameDate = game.standardDate ?? .now
            let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: gameDate)
            return date2
        }
        let sorted = groupDic.sorted(by: {
            return $0.key.date! < $1.key.date!
        })
        var newDict: [DateComponents: [Game]] = [:]
        for sort in sorted {
            newDict[sort.key] = sort.value
        }
        withAnimation {
            sortedGames = sorted
        }
    }
    
    func setFavorites() {
        favoriteGames = filteredGames?.filter({favorites.contains($0)})
    }
    
    func getTeams(for game: Game) -> (home: Team, away: Team)? {
        let strHomeTeam = game.strHomeTeam
        let strAwayTeam = game.strAwayTeam
        guard let idHomeTeam = game.idHomeTeam,
              let idAwayTeam = game.idAwayTeam,
              let foundHomeTeam = Team.getTeamInfoFrom(teamDict: self.teamsDict, teamID: idHomeTeam) ?? Team.getTeamInfoFrom(teamDict: self.teamsDictName, teamName: strHomeTeam)
                  ?? Team.getTeamInfoFrom(teams: self.teams, teamName: strHomeTeam),
              let foundAwayTeam = Team.getTeamInfoFrom(teamDict: self.teamsDict, teamID: idAwayTeam) ?? Team.getTeamInfoFrom(teamDict: self.teamsDictName, teamName: strAwayTeam)
                ?? Team.getTeamInfoFrom(teams: self.teams, teamName: strAwayTeam)
        else {
            return nil
        }
        
        return (foundHomeTeam, foundAwayTeam)
    }
    
    func handleSearch(searchString: String?) {
        if let searchString, isValidSearchString(searchString: searchString) {
            filteredGames = filteredGames?
                .filter({ game in
                    guard let (homeTeam, awayTeam) = getTeams(for: game) else { return false }
                    return (homeTeam.strTeamShort ?? "").contains(searchString) ||
                    (homeTeam.strTeam ?? "").contains(searchString) ||
                    (awayTeam.strTeamShort ?? "").contains(searchString) ||
                    (awayTeam.strTeam ?? "").contains(searchString)
                })
        }
    }
    func isValidSearchString(searchString: String) -> Bool {
        return !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func getInfo() {
        if networkFetchTask?.isCancelled ?? true || networkFetchTask == nil {
            networkState = .loading
            networkFetchTask = Task {
                restartTimer = nil
                await getData()
            }
        } else {
            networkFetchTask?.cancel()            
            getInfo()
        }
    }
    
    func dumpCaches() throws {
        teamCache?.deleteAll()
        gameCache?.deleteAll()
        liveCache?.deleteAll()
        try gameCache?.saveToDisk(with: "games")
        try teamCache?.saveToDisk(with: "teams")
        try liveCache?.saveToDisk(with: "live")
        getInfo()
    }
}

extension GameViewModel: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.webSocketTask = nil
        restartTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { [weak self] _ in
            if self?.networkState != .loaded {
                self?.getInfo()
            }
        })
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
                try await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID, debug: appStorage.debugMode)
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
