//
//  CompetitionView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI
import NukeUI
import SportsCalModel
import WidgetKit

struct CompetitionView: View {
    var league: Leagues
    @State var isShown: Bool = true
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Toggle(isOn: $isShown) {
                HStack(spacing: 12) {
                    let logoURL = colorScheme == .dark ? league.darkLogoURL : league.logoURL
                    if let logoURL {
                        LazyImage(request: ImageRequest(url: logoURL, processors: [.resize(size: CGSize(width: 28, height: 28))])) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "sportscourt.fill")
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(league.leagueName)
                }
            }
            .onChange(of: isShown) { oldValue, newValue in
                if newValue {
                    appStorage.hiddenCompetitions.removeAll(where: { $0 == league.leagueName })
                } else {
                    if !appStorage.hiddenCompetitions.contains(league.leagueName) {
                        appStorage.hiddenCompetitions.append(league.leagueName)
                    }
                }
                appStorage.syncHiddenCompetitions()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onAppear {
            isShown = !appStorage.hiddenCompetitions.contains(league.leagueName)
        }
    }
}

#Preview {
    CompetitionView(league: .Serie_A)
        .environment(UserDefaultStorage())
}
