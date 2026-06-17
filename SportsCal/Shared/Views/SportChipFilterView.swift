//
//  SportChipFilterView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SportsCalModel

enum SportChipFilter: Equatable, Hashable {
    case all
    case sport(SportType)

    func matches(_ game: Game) -> Bool {
        switch self {
        case .all:
            return true
        case .sport(let sportType):
            return game.sportType == sportType
        }
    }
}
