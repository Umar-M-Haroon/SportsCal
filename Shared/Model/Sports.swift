//
//  Sports.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/14/21.
//

import Foundation

struct Sports: Codable {
    let NHL: NHL
    let NFL: NFL
    let NBA: NBA
    let MLB: MLB
    let F1: F1
    let Soccer: Soccer
    func convertToGames(isWidget: Bool = false) -> ([Game], [Game]) {
        let nbaGames = NBA.games?
            .compactMap({Game(nbaGame: $0)}) ?? []
        let nflGames = NFL.weeks?
            .compactMap({ $0.games })
            .flatMap({ $0 })
            .map({ Game(nflGame: $0) }) ?? []
        let nhlGames = NHL.games?
            .compactMap({ Game(nhlGame: $0) }) ?? []
        let mlbGames = MLB.games?
            .compactMap({ Game(mlbGame: $0) }) ?? []
        let F1Games = F1.stage?.stages.compactMap({ stage in
            return Game(F1Stage: stage)
        }) ?? []
        
        let soccerGames = Soccer.flatMap({$0.schedules}).compactMap { Game(SoccerGame: $0.sportEvent) }
        let allGames = F1Games + soccerGames + nbaGames + nflGames + nhlGames + mlbGames
        if let game = allGames.first {
            if (isWidget) {
                return ([], game.removePastGames(games: allGames))
            }
            return (allGames, game.filtered(games: allGames))
        }
        return (allGames, allGames)
    }
}
