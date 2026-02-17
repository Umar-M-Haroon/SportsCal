//
//  File.swift
//  
//
//  Created by Umar Haroon on 3/22/23.
//

import Foundation
import Queues
import RediStack
import SportsCalModel

struct SportsCalendar: Codable {}

struct ESPNCalendarJob: AsyncScheduledJob {
    
    func run(context: Queues.QueueContext) async throws {
//        await withThrowingTaskGroup(of: [League: SportsCalendar].self) { group in
//            for league in Leagues.allCases {
//                group.addTask(operation: <#T##() async throws -> _#>)
//            }
//        }
    }
    
    func returnUpdatedEvents(events: [Game], espnEvents: [Game]) -> LiveEvent {
        let newEvents: [Game] = espnEvents.compactMap { event in
            if let foundEvent = events.first(where: {$0.strHomeTeam == event.strHomeTeam && $0.strAwayTeam == event.strAwayTeam}) {
                // Only include essential fields - strSport/strLeague are computed from idLeague
                // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                return Game(idLiveScore: foundEvent.idLiveScore, idEvent: foundEvent.idEvent, strSport: nil, idLeague: foundEvent.idLeague, strLeague: nil, idHomeTeam: foundEvent.idHomeTeam, idAwayTeam: foundEvent.idAwayTeam, strHomeTeam: foundEvent.strHomeTeam, strAwayTeam: foundEvent.strAwayTeam, strHomeTeamBadge: foundEvent.strHomeTeamBadge, strAwayTeamBadge: foundEvent.strAwayTeamBadge, intHomeScore: event.intHomeScore, intAwayScore: event.intAwayScore, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: foundEvent.strStatus, strProgress: event.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: foundEvent.strTimestamp, isCompleted: event.isCompleted, isoDate: Game.getDate(timestamp: foundEvent.strTimestamp))
            } else {
                // Only include essential fields - strSport/strLeague are computed from idLeague
                return Game(idLiveScore: event.idLiveScore, idEvent: event.idEvent, strSport: nil, idLeague: event.idLeague, strLeague: nil, idHomeTeam: event.idHomeTeam, idAwayTeam: event.idAwayTeam, strHomeTeam: event.strHomeTeam, strAwayTeam: event.strAwayTeam, strHomeTeamBadge: event.strHomeTeamBadge, strAwayTeamBadge: event.strAwayTeamBadge, intHomeScore: event.intHomeScore, intAwayScore: event.intAwayScore, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: event.strStatus, strProgress: event.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: event.strTimestamp, isoDate: Game.getDate(timestamp: event.strTimestamp))
            }
        }
        if newEvents.isEmpty {
            return LiveEvent(events: espnEvents)
        }

        return LiveEvent(events: newEvents)
    }
}
