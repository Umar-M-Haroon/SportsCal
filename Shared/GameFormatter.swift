//
//  GameFormatter.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import Foundation
import SportsCalModel

class GameFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        if let liveActivityObj = obj as? (LiveSportActivityAttributes, LiveSportActivityAttributes.ContentState) {
            return handleStringForLiveActivity(liveActivity: liveActivityObj)
            
        } else if let object = obj as? Game{
            return handleStringForGame(game: object)
        }
        return nil
    }
    
    private func handleStringForLiveActivity(liveActivity: (attr: LiveSportActivityAttributes, state: LiveSportActivityAttributes.ContentState)) -> String? {
        guard
            let leagueString = liveActivity.attr.league else { return "no league" }
       guard  let leagueInt = Int(leagueString) else { return "improper league string" }
        guard let league = Leagues(rawValue: leagueInt) else { return "unmapped league"}
       
        let status = liveActivity.state.status ?? ""
        let sport = SportType(league: league)
        switch sport {
        case .basketball:
            var finalString = "\(status)"
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr) {
                finalString += " \(12 - progress):00"
            }
            return finalString
        case .soccer:
            var finalString = "\(status)"
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr) {
                finalString = " \(progress)'"
            }
            return finalString
        case .hockey:
            var finalString = "\(status)"
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr), status == "P3", progress == 0 {
                return "FT"
            }
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr), status == "P2", progress == 0 {
                return "Intermission"
            }
            if status == "BT" {
                finalString = "Intermission"
                return finalString
            }
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr) {
                finalString += " \(20 - progress):00"
            }
            return finalString
        case .mlb:
            var finalString = "\(status)"
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr) {
                finalString += " \(progress)"
            }
            return finalString
        case .nfl:
            var finalString = "\(status)"
            if let progressStr = liveActivity.state.progress, let progress = Int(progressStr) {
                finalString += "\(15 - progress):00"
            } else if let progressStr = liveActivity.state.progress {
                finalString = progressStr
            }
            return finalString
        }
        return "no sport?"
    }
    
    private func handleStringForGame(game: Game) -> String? {
        guard
              let leagueString = game.idLeague,
              let leagueInt = Int(leagueString),
              let league = Leagues(rawValue: leagueInt)
        else {
            return nil
        }
        let status = game.strStatus ?? ""
        let sport = SportType(league: league)
        switch sport {
        case .basketball:
            var finalString = "\(status)"
            if let progressStr = game.strProgress, let progress = Int(progressStr) {
                finalString += " \(12 - progress):00"
            }
            return finalString
        case .soccer:
            var finalString = "\(status)"
            if let progressStr = game.strProgress, let progress = Int(progressStr) {
                finalString = " \(progress)'"
            }
            return finalString
        case .hockey:
            var finalString = "\(status)"
            if let progressStr = game.strProgress, let progress = Int(progressStr), status == "P3", progress == 0 {
                return "FT"
            }
            if let progressStr = game.strProgress, let progress = Int(progressStr), status == "P2", progress == 0 {
                return "Intermission"
            }
            if status == "BT" {
                finalString = "Intermission"
                return finalString
            }
            if let progressStr = game.strProgress, let progress = Int(progressStr) {
                finalString += " \(20 - progress):00"
            }
            return finalString
        case .mlb:
            var finalString = "\(status)"
            if let progressStr = game.strProgress, let progress = Int(progressStr) {
                finalString += " \(progress)"
            }
            return finalString
        case .nfl:
            var finalString = "\(status)"
            if let progressStr = game.strProgress, let progress = Int(progressStr) {
                finalString += "\(15 - progress):00"
            } else if let progressStr = game.strProgress {
                finalString = progressStr
            }
            return finalString
        }
    }
    
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return false
    }
}
