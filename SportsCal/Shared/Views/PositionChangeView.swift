//
//  PositionChangeView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/12/26.
//

import SwiftUI

/// Shows up/down arrows based on position change delta
/// Positive delta = gained positions (green up arrow), negative = lost (red down arrow)
struct PositionChangeView: View {
    let delta: Int?

    var body: some View {
        if let delta, delta != 0 {
            HStack(spacing: 1) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                Text("\(abs(delta))")
            }
            .font(.caption2)
            .foregroundColor(delta > 0 ? .green : .red)
        }
    }
}
