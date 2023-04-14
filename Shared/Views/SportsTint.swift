//
//  SportsTint.swift
//  SportsCal
//
//  Created by Umar Haroon on 1/21/23.
//

import SwiftUI
import SportsCalModel

struct SportsTint: ViewModifier {
    let sport: SportType
    func body(content: Content) -> some View {
        if sport == .basketball {
            content
                .foregroundColor(.orange)
        }
        if sport == .mlb {
            content
                .foregroundColor(.white)
                .background(.red, in: Circle())
        }
        if sport == .nfl {
            content
                .foregroundColor(.brown)
        }
        if sport == .hockey {
            content
                .foregroundColor(.primary)
        }
        if sport == .soccer {
            content
                .foregroundColor(.primary)
        }
    }
}
