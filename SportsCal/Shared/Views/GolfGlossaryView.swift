//
//  GolfGlossaryView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/12/26.
//

import SwiftUI

/// A popover explaining common golf terms used in the scorecard and tournament views.
struct GolfGlossaryView: View {
    @Environment(\.dismiss) private var dismiss

    private let terms: [(term: String, definition: String)] = [
        ("Par", "The expected number of strokes for a hole or course. A \"par 4\" means a skilled golfer should complete the hole in 4 strokes."),
        ("Birdie", "One stroke under par (e.g., 3 on a par 4). Shown in green."),
        ("Eagle", "Two strokes under par (e.g., 3 on a par 5). Shown in teal."),
        ("Ace / Hole-in-One", "Completing a hole in a single stroke. Shown in gold."),
        ("Bogey", "One stroke over par (e.g., 5 on a par 4). Shown in orange/red."),
        ("Double Bogey+", "Two or more strokes over par. Shown in dark red."),
        ("OUT", "The front nine — holes 1 through 9. Named because you're heading \"out\" from the clubhouse."),
        ("IN", "The back nine — holes 10 through 18. Named because you're heading back \"in\" to the clubhouse."),
        ("TOT", "Total strokes for the round (OUT + IN)."),
        ("Thru", "How many holes a player has completed in the current round. \"F\" means finished."),
        ("E", "Even par — the player's score matches the expected score exactly."),
        ("Cut", "After round 2, only the top ~50 players advance. The rest are \"cut\" and eliminated."),
        ("FW (Fairways)", "How many fairways the player hit off the tee, shown as a fraction (e.g., 9/14)."),
        ("GIR (Greens in Regulation)", "How many greens the player reached in the expected number of strokes."),
        ("-5, +2", "Score relative to par. Negative is good (under par), positive is bad (over par)."),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(terms, id: \.term) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.term)
                            .font(.subheadline.bold())
                        Text(item.definition)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Golf Terms")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
