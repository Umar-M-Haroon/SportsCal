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
                        .font(.headline)

                    Text("Select the sports you follow")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(SportType.allCases, id: \.self) { sport in
                        Button {
                            if selectedSports.contains(sport) {
                                selectedSports.remove(sport)
                            } else {
                                selectedSports.insert(sport)
                            }
                        } label: {
                            HStack {
                                Image(systemName: sport.widgetSystemImage)
                                    .foregroundStyle(sport.widgetColor)
                                    .frame(width: 24)
                                Text(sport.capitalized)
                                    .font(.system(size: 14))
                                Spacer()
                                if selectedSports.contains(sport) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
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
