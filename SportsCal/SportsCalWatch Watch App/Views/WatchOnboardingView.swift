//
//  WatchOnboardingView.swift
//  SportsCalWatch
//
//  First-launch sport selection when no preferences have been synced from iPhone.
//

import SwiftUI
import SportsCalModel

struct WatchOnboardingView: View {
    @Environment(WatchViewModel.self) private var viewModel
    @Binding var isPresented: Bool

    @State private var selectedSports: Set<SportType> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Pick Your Sports")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(WatchTokens.ink)

                    Text("Select the sports you follow")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WatchTokens.inkSoft)

                    ForEach(SportType.allCases, id: \.self) { sport in
                        Button {
                            if selectedSports.contains(sport) {
                                selectedSports.remove(sport)
                            } else {
                                selectedSports.insert(sport)
                            }
                        } label: {
                            let accent = WatchTokens.sport(sport)
                            let isSelected = selectedSports.contains(sport)
                            HStack {
                                Image(systemName: sport.widgetSystemImage)
                                    .foregroundStyle(accent)
                                    .frame(width: 24)
                                Text(sport.capitalized)
                                    .font(.system(size: 14, design: .rounded).weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(WatchTokens.ink)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .overlay(alignment: .leading) {
                                if isSelected {
                                    Rectangle()
                                        .fill(accent)
                                        .frame(width: 2)
                                        .padding(.vertical, 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Get Started") {
                        applyAndDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSports.isEmpty)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func applyAndDismiss() {
        viewModel.enabledSports = selectedSports

        // Save to local UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(selectedSports.contains(.basketball), forKey: "shouldShowNBA")
        defaults.set(selectedSports.contains(.soccer), forKey: "shouldShowSoccer")
        defaults.set(selectedSports.contains(.hockey), forKey: "shouldShowNHL")
        defaults.set(selectedSports.contains(.mlb), forKey: "shouldShowMLB")
        defaults.set(selectedSports.contains(.nfl), forKey: "shouldShowNFL")
        defaults.set(selectedSports.contains(.golf), forKey: "shouldShowGolf")
        defaults.set(selectedSports.contains(.tennis), forKey: "shouldShowTennis")
        defaults.set(selectedSports.contains(.racing), forKey: "shouldShowRacing")
        defaults.set(true, forKey: "watchOnboardingComplete")

        isPresented = false
        Task { await viewModel.fetchSchedule() }
    }
}
