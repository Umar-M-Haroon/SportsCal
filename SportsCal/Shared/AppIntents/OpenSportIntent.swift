//
//  OpenSportIntent.swift
//  SportsCal
//
//  Siri: "Open NBA games in SportsCal"
//  Deep links to the Games tab filtered by sport.
//

import AppIntents
import SportsCalModel

struct OpenSportIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sport"
    static var description: IntentDescription = "Opens SportsCal to show games for a specific sport."

    @Parameter(title: "Sport")
    var sport: SportAppEnum

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Write the requested sport to app group so the app can pick it up on launch
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        defaults?.set(sport.rawValue, forKey: "intentOpenSport")

        return .result(dialog: "Opening \(sport.sportType.capitalized) games in SportsCal.")
    }
}
