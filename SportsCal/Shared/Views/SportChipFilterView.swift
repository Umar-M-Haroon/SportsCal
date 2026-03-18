//
//  SportChipFilterView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
import TipKit

enum SportChipFilter: Equatable, Hashable {
    case all
    case sport(SportType)

    func matches(_ game: Game) -> Bool {
        switch self {
        case .all:
            return true
        case .sport(let sportType):
            return game.sportType == sportType
        }
    }
}

struct SportChipFilterView: View {
    @Binding var selectedFilter: SportChipFilter
    @Binding var showSportPicker: Bool
    @Binding var browseSport: SportType?
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel

    var body: some View {
        let enabledSports = storage.enabledSports
        let disabledSports = storage.orderedSports.filter { !enabledSports.contains($0) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if enabledSports.count > 1 {
                    chipButton(label: "All", icon: nil, filter: .all)
                }
                ForEach(enabledSports, id: \.self) { sport in
                    let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
                    chipButton(
                        label: sport.capitalized,
                        icon: sport.systemImage,
                        sport: sport,
                        filter: .sport(sport),
                        liveCount: liveCount
                    )
                }
                if !disabledSports.isEmpty {
                    Divider()
                        .frame(height: 20)
                    ForEach(disabledSports, id: \.self) { sport in
                        disabledChipButton(sport: sport)
                    }
                }
                addButton
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: selectedFilter)
        .popoverTip(SportFilterTip())
    }

    private var addButton: some View {
        Button {
            showSportPicker = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .buttonStyle(BorderedButtonStyle())
        .buttonBorderShape(.capsule)
    }

    private func disabledChipButton(sport: SportType) -> some View {
        Button {
            browseSport = sport
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sport.systemImage)
                    .font(.caption)
                    .modifier(SportsTint(sport: sport))
                Text(sport.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonBorderShape(.capsule)
        }
        .buttonStyle(BorderedButtonStyle())
        .buttonBorderShape(.capsule)
        .opacity(0.5)
    }

    private func chipButton(label: String, icon: String? = nil, sport: SportType? = nil, filter: SportChipFilter, liveCount: Int = 0) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected && filter != .all {
                    selectedFilter = .all
                } else {
                    selectedFilter = filter
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let icon, let sport {
                    Image(systemName: icon)
                        .font(.caption)
                        .modifier(SportsTint(sport: sport))
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? .white : .red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.red : Color.red.opacity(0.15), in: Capsule())
                }
            }
            .buttonBorderShape(.capsule)
        }
        .buttonBorderStyle(isSelected)
        .buttonBorderShape(.capsule)
    }
}

extension Button {
    @ViewBuilder
    func buttonBorderStyle(_ isSelected: Bool) -> some View {
        if isSelected {
            self.buttonStyle(BorderedProminentButtonStyle())
        } else {
            self.buttonStyle(BorderedButtonStyle())
        }
    }
}
