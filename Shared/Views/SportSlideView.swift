//
//  SportSlideView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 7/7/23.
//

import SwiftUI

struct SportSlideView: View {
    @Binding var shouldShowButton: Bool
    var body: some View {
        Button {
            withAnimation(.spring()) {
                shouldShowButton.toggle()
            }
        } label: {
            Image(systemName: "sportscourt")
        }
    }
}

extension Animation {
    static func ripple(index: Int) -> Animation {
        Animation.spring()
            .speed(0.01)
            .delay(0.05 * Double(index))
    }
}
