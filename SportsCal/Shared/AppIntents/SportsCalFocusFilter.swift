//
//  SportsCalFocusFilter.swift
//  SportsCal
//
//  Focus Filter: allows users to configure which sports appear when a Focus is active.
//  Settings → Focus → [Focus Name] → Add Filter → SportsCal
//

#if os(iOS)
import AppIntents

struct SportsCalFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Sport Filters"
    static var description: IntentDescription = "Choose which sports to show when this Focus is active."

    @Parameter(title: "Basketball", default: true)
    var showBasketball: Bool

    @Parameter(title: "Soccer", default: true)
    var showSoccer: Bool

    @Parameter(title: "Hockey", default: true)
    var showHockey: Bool

    @Parameter(title: "Baseball", default: true)
    var showMLB: Bool

    @Parameter(title: "Football", default: true)
    var showNFL: Bool

    @Parameter(title: "Golf", default: true)
    var showGolf: Bool

    @Parameter(title: "Tennis", default: true)
    var showTennis: Bool

    @Parameter(title: "Racing", default: true)
    var showRacing: Bool

    var displayRepresentation: DisplayRepresentation {
        var enabledSports: [String] = []
        if showBasketball { enabledSports.append("NBA") }
        if showSoccer { enabledSports.append("Soccer") }
        if showHockey { enabledSports.append("NHL") }
        if showMLB { enabledSports.append("MLB") }
        if showNFL { enabledSports.append("NFL") }
        if showGolf { enabledSports.append("Golf") }
        if showTennis { enabledSports.append("Tennis") }
        if showRacing { enabledSports.append("F1") }

        let subtitle = enabledSports.isEmpty ? "No sports" : enabledSports.joined(separator: ", ")
        return DisplayRepresentation(title: "Sport Filters", subtitle: "\(subtitle)")
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        defaults?.set(true, forKey: "focusFilterActive")
        defaults?.set(showBasketball, forKey: "focus_shouldShowNBA")
        defaults?.set(showSoccer, forKey: "focus_shouldShowSoccer")
        defaults?.set(showHockey, forKey: "focus_shouldShowNHL")
        defaults?.set(showMLB, forKey: "focus_shouldShowMLB")
        defaults?.set(showNFL, forKey: "focus_shouldShowNFL")
        defaults?.set(showGolf, forKey: "focus_shouldShowGolf")
        defaults?.set(showTennis, forKey: "focus_shouldShowTennis")
        defaults?.set(showRacing, forKey: "focus_shouldShowRacing")
        return .result()
    }
}
#endif
