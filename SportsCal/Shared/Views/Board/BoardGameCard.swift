//
//  BoardGameCard.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

extension EnvironmentValues {
    /// The board game shown in the Mac inspector; its card draws the selection ring.
    @Entry var boardSelectedGameID: String?
}

struct BoardGameCard<Content: View>: View {
    var gameID: String? = nil
    let isFavorite: Bool
    let isLive: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.boardSelectedGameID) private var selectedGameID

    private var isSelected: Bool { gameID != nil && gameID == selectedGameID }

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            // Selection only: live games already show a red clock and favorites a
            // star, so neither draws a border that reads as a selection.
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.appAccent, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(4)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
