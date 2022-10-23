//
//  Game.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/21/21.
//

import Foundation

struct Game: Identifiable {
    var home: String
    var away: String
    var gameDate: Date
    var sport: SportTypes
    var id: String
    var competition: Competition? = nil
    var homeScore: Int?
    var awayScore: Int?
    var isInPast: Bool {
        return gameDate.timeIntervalSinceNow < 0
    }
    init(nbaGame: NBAGames) {
        guard let homeTeam = nbaGame.home?.name,
              let awayTeam = nbaGame.away?.name,
              let scheduledDate = nbaGame.scheduled,
              let id = nbaGame.id else {
                  self.home = ""
                  self.away = ""
                  self.gameDate = Date()
                  self.id = ""
                  self.sport = .NBA
                  return
              }
        self.homeScore = nbaGame.home_points
        self.awayScore = nbaGame.away_points
        self.home = homeTeam
        self.away = awayTeam
        self.gameDate = Date()
        self.sport = .NBA
        self.id = id
        self.gameDate = format(scheduledDate)
    }
    init(nflGame: NFLGames) {
        guard let homeTeam = nflGame.home?.name,
              let awayTeam = nflGame.away?.name,
              let scheduledDate = nflGame.scheduled,
              let id = nflGame.id else {
                  self.home = ""
                  self.away = ""
                  self.gameDate = Date()
                  self.id = ""
                  self.sport = .NFL
                  return
              }
        self.homeScore = nflGame.scoring?.home_points
        self.awayScore = nflGame.scoring?.away_points
        self.home = homeTeam
        self.away = awayTeam
        self.gameDate = Date()
        self.sport = .NFL
        self.id = id
        self.gameDate = format(scheduledDate)
    }
    
    init(nhlGame: NHLGames) {
        guard let homeTeam = nhlGame.home?.name,
              let awayTeam = nhlGame.away?.name,
              let scheduledDate = nhlGame.scheduled,
              let id = nhlGame.id else {
                  self.home = ""
                  self.away = ""
                  self.gameDate = Date()
                  self.id = ""
                  self.sport = .NHL
                  return
              }
        self.homeScore = nhlGame.home_points
        self.awayScore = nhlGame.away_points
        self.home = homeTeam
        self.away = awayTeam
        self.gameDate = Date()
        self.sport = .NHL
        self.id = id
        self.gameDate = format(scheduledDate)
    }
    init(mlbGame: MLBGames) {
        guard let homeTeam = mlbGame.home?.name,
              let awayTeam = mlbGame.away?.name,
              let scheduledDate = mlbGame.scheduled,
              let id = mlbGame.id else {
                  self.home = ""
                  self.away = ""
                  self.gameDate = Date()
                  self.id = ""
                  self.sport = .MLB
                  return
              }
        self.home = homeTeam
        self.away = awayTeam
        self.gameDate = Date()
        self.sport = .MLB
        self.id = id
        self.gameDate = format(scheduledDate)
    }
    init(F1Stage: StageElement) {
        self.home = F1Stage.stageDescription
        self.away = ""
        self.gameDate = Date()
        self.sport = .F1
        self.id = F1Stage.id
        self.gameDate = format(F1Stage.scheduled)
    }
    init(SoccerGame: SportEvent) {
        guard let homeName = SoccerGame.competitors.first(where: {$0.qualifier == .home})?.name,
              let awayName = SoccerGame.competitors.first(where: {$0.qualifier == .away})?.name else {
                  self.home = "Real Madrid"
                  self.away = "FC Barcelona"
                  self.gameDate = Date()
                  self.sport = .Soccer
                  self.id = SoccerGame.id
                  return
              }
        self.home = homeName
        self.away = awayName
        self.gameDate = Date()
        self.sport = .Soccer
        self.id = SoccerGame.id
        self.gameDate = format(SoccerGame.startTime)
        self.competition = SoccerGame.sportEventContext.competition
    }
    
    
    func format(_ scheduleString: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = dateFormatter.date(from: scheduleString) else { return Date() }
        return date
    }
    func sortByDate(games: [Game]) -> Array<(key: DateComponents, value: Array<Game>)>  {
        let groupDic = Dictionary(grouping: games) { game -> DateComponents in
            let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: game.gameDate)
            return date2
        }
        let sorted = groupDic.sorted(by: {
            if UserDefaultStorage().soonestOnTop {
                return $0.key.date! < $1.key.date!
            }
            return $0.key.date! > $1.key.date!
        })
        var newDict: [DateComponents: [Game]] = [:]
        for sort in sorted {
            newDict[sort.key] = sort.value
        }
        
        return sorted
    }
    func isValidForDuration(duration: Durations, components: DateComponents) -> Bool {
        if components.month ?? 0 < 0 || components.day ?? 0 < 0 { return false }
        var isValid: Bool = true
        switch duration {
        case .oneWeek:
            isValid = components.day ?? 0 < 7 && components.month == 0
            break
        case .twoWeeks:
            isValid = components.day ?? 0 < 14 && components.month == 0
            break
        case .threeWeeks:
            isValid = components.day ?? 0 < 21 && components.month == 0
            break
        case .oneMonth:
            isValid = components.month ?? 0 < 1
            break
        case .twoMonths:
            isValid = components.month ?? 0 < 2
            break
        case .sixMonths:
            isValid = components.month ?? 0 < 6
            break
        case .oneYear:
            isValid = components.month ?? 0 < 12
            break
        }
        return isValid
    }
    
    func filtered(games: [Game]) -> [Game] {
        let calendar = Calendar.current
        let storage = UserDefaultStorage()
        return games.filter({ game in
            let components = calendar.dateComponents([.day, .month, .year], from: Date(), to: game.gameDate)
            let pastComponents = calendar.dateComponents([.day, .month, .year], from: game.gameDate, to: Date())
            let duration = storage.durations
            let isValid: Bool = isValidForDuration(duration: duration, components: components)
            
            if !isValid { return false }
            
            var shouldHideDueToHiddenCompetition = false
            if let competition = game.competition {
                shouldHideDueToHiddenCompetition = isCompetitionHidden(competition: competition.name)
            }
            
//            return true
            if storage.hidePastEvents {
                print("⚠️ hiding past events")
                return isValid && (pastComponents.day ?? 0 > 0) && isValidSport(game: game) && !shouldHideDueToHiddenCompetition
            }
            return (isValid && isValidForDuration(duration: storage.hidePastGamesDuration, components: pastComponents)) && isValidSport(game: game) && !shouldHideDueToHiddenCompetition
//           return isValid && isValidSport(game: game)
        })
    }
    func removePastGames(games: [Game]) -> [Game] {
        return games.filter({ game in
            return game.gameDate.timeIntervalSinceNow > 0
        })
    }
    func isCompetitionHidden(competition: String) -> Bool {
        switch competition {
        case "Coppa Italia":
            return UserDefaultStorage().hideCoppaItalia
        case "Eredivisie":
            return UserDefaultStorage().hideEredivisie
        case "Bundesliga":
            return UserDefaultStorage().hideBundesliga
        case "Ligue 1":
            return UserDefaultStorage().hideLigue1
        case "Serie A":
            return UserDefaultStorage().hideSerieA
        case "EFL Cup":
            return UserDefaultStorage().hideEFLCup
        case "Championship":
            return UserDefaultStorage().hideChampionship
        case "Premier League":
            return UserDefaultStorage().hidePremierLeague
        case "LaLiga":
            return UserDefaultStorage().hideLaLiga
        case "UEFA Champions League":
            return UserDefaultStorage().hideChampionsLeague
        default:
            return false
        }
    }
    func isValidSport(game: Game) -> Bool {
        if !UserDefaultStorage().shouldShowF1{
            if game.sport == .F1 {
                return false
            }
        }
        if !UserDefaultStorage().shouldShowSoccer {
            if game.sport == .Soccer {
                return false
            }
        }
        if !UserDefaultStorage().shouldShowNHL {
            if game.sport == .NHL {
                return false
            }
        }
        if !UserDefaultStorage().shouldShowNFL {
            if game.sport == .NFL {
                return false
            }
        }
        if !UserDefaultStorage().shouldShowMLB {
            if game.sport == .MLB {
                return false
            }
        }
        if !UserDefaultStorage().shouldShowNBA {
            if game.sport == .NBA {
                return false
            }
        }
        return true
    }
}

extension Game {
    static func sampleGame() -> Game {
        Game(nbaGame: .init(id: "test", status: "test", title: "Test Game", coverage: "ESPN", scheduled: "IDK", home_points: 82, away_points: 80, track_on_court: true, sr_id: "test", reference: "test", time_zones: .init(venue: "Barclays", home: "Warriors", away: "Bucks"), venue: nil, broadcasts: nil, home: .init(name: "Warriors", alias: "GSW", id: "GSW", sr_id: "Test", reference: "test"), away: .init(name: "Bucks", alias: "MIL", id: "Bucks", sr_id: "Bucks", reference: "bucks")))
    }
}
