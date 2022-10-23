//
//  GameViewModel.swift
//  SportsCal
//
//  Created by Umar Haroon on 8/13/22.
//

import Foundation
import SwiftUI
import Combine
@MainActor public class GameViewModel: ObservableObject {
    var appStorage = UserDefaultStorage()
    var favorites: Favorites = Favorites()
    @Published var totalGames: [Game]?
    @Published var filteredGames: [Game]?
    @Published var cancellable: AnyCancellable?
    @Published var teamString: String? = ""
    @Published var favoriteGames: [Game] = []
    @Published var networkState: NetworkState = .loading
    
    @available(iOS 15.0.0, *)
    private func getData() async {
#if DEBUG
        if ProcessInfo.processInfo.environment["FULL_DATA"] != nil {
            let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "sports", ofType: "json")!))
            let nbaData = try! JSONDecoder().decode(Sports.self, from: data)
            (totalGames, filteredGames) = nbaData.convertToGames()
            let competitions = totalGames?.compactMap({$0})
                .filter({$0.sport == .Soccer}).compactMap({$0.competition?.name})
            let competitionsSet = Set.init(arrayLiteral: competitions ?? [])
            print(competitionsSet)
        }
#else
        do {
            let result = try await NetworkHandler.handleCall(year: "2020")
            (totalGames, filteredGames) = result.convertToGames()
            
            favoriteGames = result.favoritesToGames(games: filteredGames ?? [], favorites: favorites)
            
            networkState = .loaded
        } catch let e {
            print(e)
            print(e.localizedDescription)
            networkState = .failed
        }
                #endif
    }
    func filterSports() {
        print("⚠️ sports duration or selected sport changed, filtering")
        print("⚠️ should show F1 \(appStorage.shouldShowF1)")
        print("⚠️ should show NFL \(appStorage.shouldShowNFL)")
        print("⚠️ should show NBA \(appStorage.shouldShowNBA)")
        print("⚠️ should show NHL \(appStorage.shouldShowNHL)")
        print("⚠️ should show Soccer \(appStorage.shouldShowSoccer)")
        print("⚠️ should show MLB \(appStorage.shouldShowMLB)")
        if let first = filteredGames?.first {
            if let games = filteredGames {
                filteredGames = first.filtered(games: totalGames ?? [])
                favoriteGames = games.filter({ favorites.contains($0) })
                print(favoriteGames.count)
            }
        } else {
            filteredGames = totalGames?.first?.filtered(games: totalGames ?? [])
            favoriteGames = filteredGames?.filter({ favorites.contains($0) }) ?? []
            print(favoriteGames.count)
        }
        print("⚠️ total amount of games, \(totalGames?.count) filtered result \(filteredGames?.count)")
    }
    func getInfo() {
        if #available(iOS 15.0, *) {
            Task {
                await getData()
            }
        } else {
            cancellable = NetworkHandler.handleCall()
                .sink { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let err):
                        print(err.localizedDescription)
                    }
                } receiveValue: { [weak self] sports  in
                    guard let self = self else { return }
                    (self.totalGames, self.filteredGames) = sports.convertToGames()
                }
        }
    }
}
