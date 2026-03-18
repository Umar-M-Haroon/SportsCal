//
//  BoardGameCard.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

struct BoardGameCard<Content: View>: View {
    let isFavorite: Bool
    let isLive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isFavorite {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.yellow.opacity(0.5), lineWidth: 1.5)
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
            .overlay {
                if isLive {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.red.opacity(0.6), lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
