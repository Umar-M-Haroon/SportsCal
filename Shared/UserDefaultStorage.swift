//
//  UserDefaultStorage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/14/21.
//

import Foundation
import SwiftUI
import SportsCalModel
import Combine

class UserDefaultStorage: NSObject, ObservableObject {
    @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @AppStorage("hidesPastEvents") var hidePastEvents: Bool = true
    @AppStorage("soonestOnTop") var soonestOnTop: Bool = true
    @AppStorage("duration") var durations: Durations = .threeWeeks
    @AppStorage("launches") var launches: Int = 0
    @AppStorage("dateFormat") var dateFormat: Int = 1
    @AppStorage("hidePastGamesDuration") var hidePastGamesDuration: Durations = .threeWeeks
    @AppStorage("showStartTime") var showStartTime: Bool = true
    @AppStorage("debugMode") var debugMode: Bool = false
    @AppStorage("hiddenCompetitions") var hiddenCompetitions: [String] = []
    @AppStorage("useRelativeValue") var useRelativeValue: Bool = false

    func switchTo(sportType: SportType) {
        switch sportType {
        case .hockey:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = true
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .nfl:
            shouldShowNFL = true
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .basketball:
            shouldShowNFL = false
            shouldShowNBA = true
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .mlb:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = true
            break
        case .soccer:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = true
            shouldShowMLB = false
            break
        }
    }
}
extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
