//
//  SnapshotFixtures.swift
//  SportsCalTests
//
//  Fixture factories for SwiftUI snapshot tests. Builds on DebugGameFactory
//  and constructs the environment objects views need to render standalone.
//

import Foundation
import SwiftUI
@testable import Scoreline
import SportsCalModel

enum SnapshotGameState {
    case upcoming
    case live
    case final
}

enum SnapshotVariant {
    case plain
    case playoff
    case twoLeg
    case major
}

enum Fixtures {

    // MARK: - Games

    static func game(
        sport: SportType,
        state: SnapshotGameState = .upcoming,
        variant: SnapshotVariant = .plain
    ) -> Game {
        switch (sport, state, variant) {
        case (.racing, .upcoming, _):
            return DebugGameFactory.createFakeUpcomingRace()
        case (.racing, .live, _), (.racing, .final, _):
            return DebugGameFactory.createFakeLiveRace()
        case (.golf, .upcoming, _), (.tennis, .upcoming, _):
            return DebugGameFactory.createFakeUpcomingTournament(sport: sport)
        case (.golf, .live, .major):
            return DebugGameFactory.createFakeLiveTournament(sport: .golf, isMajor: true)
        case (.golf, .live, _), (.tennis, .live, _):
            return DebugGameFactory.createFakeLiveTournament(sport: sport)
        case (.golf, .final, _), (.tennis, .final, _):
            return DebugGameFactory.createFakeLiveTournament(sport: sport)
        case (_, .upcoming, _):
            return DebugGameFactory.createFakeUpcomingGame(sport: sport, secondsFromNow: 3600)
        case (_, .live, .playoff):
            return DebugGameFactory.createFakePlayoffGame(sport: sport)
        case (.soccer, .live, .twoLeg):
            return DebugGameFactory.createFakeTwoLegSoccer()
        case (_, .live, _):
            return DebugGameFactory.createFakeLiveGame(sport: sport)
        case (_, .final, _):
            return DebugGameFactory.createFakeFinalGame(sport: sport)
        }
    }

    static func teams(for game: Game) -> (home: Team, away: Team) {
        DebugGameFactory.fakeTeams(for: game)
    }

    // MARK: - Environment objects

    @MainActor
    static func storage(enableAllSports: Bool = true) -> UserDefaultStorage {
        let storage = UserDefaultStorage()
        if enableAllSports {
            storage.shouldShowNBA = true
            storage.shouldShowNFL = true
            storage.shouldShowNHL = true
            storage.shouldShowSoccer = true
            storage.shouldShowMLB = true
            storage.shouldShowGolf = true
            storage.shouldShowTennis = true
            storage.shouldShowRacing = true
        }
        return storage
    }

    @MainActor
    static func favorites(teamIds: [String] = []) -> Favorites {
        let favorites = Favorites()
        for id in teamIds {
            favorites.add(id)
        }
        return favorites
    }

    @MainActor
    static func viewModel(
        games: [Game] = [],
        liveEvents: [Game] = [],
        storage: UserDefaultStorage? = nil,
        favorites: Favorites? = nil
    ) -> GameViewModel {
        let store = storage ?? Self.storage()
        let favs = favorites ?? Self.favorites()
        let vm = GameViewModel(
            appStorage: store,
            favorites: favs,
            totalGames: games,
            filteredGames: games,
            networkState: games.isEmpty ? .loading : .loaded
        )
        vm.liveEvents = liveEvents
        return vm
    }

    @MainActor
    static func engagementTracker() -> EngagementTracker {
        EngagementTracker()
    }

    @MainActor
    static func subscriptionManager(isPro: Bool = false) -> SubscriptionManager {
        SubscriptionManager(forTesting: isPro)
    }

    #if os(iOS)
    @MainActor
    static func adManager() -> NativeAdManager {
        NativeAdManager()
    }
    #endif

    // MARK: - Leaderboard / F1 data

    static func golfLeaderboard(top: Int = 5) -> [LeaderboardEntry] {
        let names = [
            ("Scottie Scheffler", "-14"),
            ("Rory McIlroy", "-12"),
            ("Xander Schauffele", "-10"),
            ("Collin Morikawa", "-9"),
            ("Jon Rahm", "-8"),
            ("Viktor Hovland", "-7"),
            ("Ludvig Åberg", "-6")
        ]
        return names.prefix(top).enumerated().map { index, entry in
            LeaderboardEntry(
                name: entry.0,
                score: entry.1,
                position: index + 1,
                rounds: ["68", "70", "67"]
            )
        }
    }

    static func f1Standings() -> F1Standings {
        F1Standings(
            driverStandings: [
                F1DriverStanding(position: 1, driverName: "Max Verstappen", constructorName: "Red Bull", points: 437, wins: 14),
                F1DriverStanding(position: 2, driverName: "Lando Norris", constructorName: "McLaren", points: 374, wins: 4),
                F1DriverStanding(position: 3, driverName: "Charles Leclerc", constructorName: "Ferrari", points: 356, wins: 3)
            ],
            constructorStandings: [
                F1ConstructorStanding(position: 1, constructorName: "McLaren", points: 666, wins: 6),
                F1ConstructorStanding(position: 2, constructorName: "Ferrari", points: 652, wins: 5),
                F1ConstructorStanding(position: 3, constructorName: "Red Bull", points: 589, wins: 9)
            ]
        )
    }
}
