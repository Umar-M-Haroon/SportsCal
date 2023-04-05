//
//  IntentHandler.swift
//  SoccerLeaguesWidgetIntentExtension
//
//  Created by Umar Haroon on 12/8/22.
//

import Intents
import SportsCalModel
class IntentHandler: INExtension, ConfigurationIntentHandling {
    func provideSoccerLeagueOptionsCollection(for intent: ConfigurationIntent, with completion: @escaping (INObjectCollection<NSString>?, Error?) -> Void) {
        
        var leagueStrings = Leagues.allCases.filter({$0.isSoccer}).map({NSString(string: $0.leagueName)})
        leagueStrings.append("All Leagues")
        completion(.init(items: leagueStrings), nil)
    }
    
    override func handler(for intent: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.
        
        return self
    }
    
}
