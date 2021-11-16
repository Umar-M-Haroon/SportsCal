//
//  UserDefaultStorage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/14/21.
//

import Foundation
import SwiftUI

class UserDefaultStorage: ObservableObject, Equatable {
    static func == (lhs: UserDefaultStorage, rhs: UserDefaultStorage) -> Bool {
        return lhs.shouldShowF1 == rhs.shouldShowF1 &&
               lhs.hidePastEvents == rhs.hidePastEvents &&
        lhs.shouldShowNBA == rhs.shouldShowNBA &&
        lhs.shouldShowNFL == rhs.shouldShowNFL &&
        lhs.shouldShowNHL == rhs.shouldShowNHL &&
        lhs.shouldShowSoccer == rhs.shouldShowSoccer &&
        lhs.shouldShowMLB == rhs.shouldShowMLB &&
        lhs.shouldShowOnboarding == rhs.shouldShowOnboarding &&
        lhs.hidePastEvents == rhs.hidePastEvents &&
        lhs.soonestOnTop == rhs.soonestOnTop &&
        lhs.durations == rhs.durations
    }
    
    @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @AppStorage("shouldShowF1") var shouldShowF1: Bool = false
    @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @AppStorage("hidesPastEvents") var hidePastEvents: Bool = false
    @AppStorage("soonestOnTop") var soonestOnTop: Bool = true
    @AppStorage("duration") var durations: Durations = .oneWeek
    
    func switchTo(sportType: SportTypes) {
        switch sportType {
        case .NHL:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = true
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .NFL:
            shouldShowF1 = false
            shouldShowNFL = true
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .NBA:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = true
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .MLB:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = true
            break
        case .F1:
            shouldShowF1 = true
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .Soccer:
            shouldShowF1 = false
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = true
            shouldShowMLB = false
            break
        }
    }
}
