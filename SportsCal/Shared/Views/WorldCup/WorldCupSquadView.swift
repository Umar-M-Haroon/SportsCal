//
//  WorldCupSquadView.swift
//  SportsCal
//
//  A national team's squad, fetched lazily from the server (which fetches+caches
//  the ESPN roster on demand).
//

import SwiftUI
import SportsCalModel

struct WorldCupSquadView: View {
    let teamID: String
    let teamName: String

    @State private var squad: WorldCupSquad?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace3) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, .appSpace5)
                } else if let squad, !squad.players.isEmpty {
                    ForEach(Array(squad.players.enumerated()), id: \.offset) { _, player in
                        playerRow(player)
                        Divider().background(Color.appDivider)
                    }
                } else {
                    Text(errorMessage ?? "Squad not available yet.")
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, .appSpace5)
                }
            }
            .padding(.appSpace4)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(teamName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task { await load() }
    }

    private func playerRow(_ player: WorldCupSquadPlayer) -> some View {
        HStack(spacing: .appSpace3) {
            if let jersey = player.jersey, !jersey.isEmpty {
                Text(jersey)
                    .font(.appFootnote)
                    .foregroundStyle(Color.appInkFaint)
                    .frame(width: 28, alignment: .leading)
            }
            HeadshotView(url: player.headshotURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.appCallout)
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                if let position = player.position, !position.isEmpty {
                    Text(position)
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                }
            }
            Spacer(minLength: 0)
            if let age = player.age {
                Text("Age \(age)")
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkFaint)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            squad = try await NetworkHandler.getWorldCupSquad(teamID: teamID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
