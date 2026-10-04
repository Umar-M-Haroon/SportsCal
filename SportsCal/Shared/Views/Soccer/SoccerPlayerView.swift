//
//  SoccerPlayerView.swift
//  SportsCal
//
//  A soccer player's page: bio, this season's goals and assists across every
//  competition, a line per competition, the last five matches and the next
//  fixture. Loaded on demand from `/soccer/player/:athleteID` (ESPN athlete ids,
//  which lineups and leader lists carry).
//
//  `SoccerPlayerLink` pushes it. Like `TeamDetailLink`, it is a view-destination
//  link: detail screens mix it with other view links, and a value link there
//  would re-push the current screen.
//

import SwiftUI
import SportsCalModel

struct SoccerPlayerLink<Label: View>: View {
    let athleteID: String
    let name: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            SoccerPlayerView(athleteID: athleteID, name: name)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

struct SoccerPlayerView: View {
    let athleteID: String
    /// Shown as the title while the profile loads.
    let name: String

    @State private var profile: SoccerPlayerProfile?
    @State private var isLoading = true
    @State private var failed = false

    /// `profile` pre-fills the page (previews); it still refreshes on appear.
    init(athleteID: String, name: String, profile: SoccerPlayerProfile? = nil) {
        self.athleteID = athleteID
        self.name = name
        _profile = State(initialValue: profile)
    }

    var body: some View {
        ScrollView {
            if let profile {
                VStack(alignment: .leading, spacing: .appSpace4) {
                    header(profile)
                    if !profile.seasons.isEmpty {
                        totals(profile)
                        seasonsCard(profile.seasons)
                    }
                    if !profile.recentMatches.isEmpty {
                        recentCard(profile.recentMatches)
                    }
                    if let next = profile.nextMatch {
                        nextCard(next)
                    }
                }
                .padding(.horizontal, .appSpace4)
                .padding(.vertical, .appSpace3)
            } else if failed {
                ContentUnavailableView("Player Unavailable", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("There's no profile for \(name) yet."))
                    .padding(.top, 80)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay { if isLoading && profile == nil { ProgressView() } }
        .navigationTitle(profile?.name ?? name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await NetworkHandler.getSoccerPlayer(athleteID: athleteID)
            failed = false
        } catch {
            failed = profile == nil
        }
    }

    // MARK: Header

    private func header(_ profile: SoccerPlayerProfile) -> some View {
        HStack(alignment: .top, spacing: .appSpace3) {
            ZStack {
                Circle().fill(Color.app(.soccer).opacity(0.15))
                Text(profile.jersey ?? initials(profile.name))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.app(.soccer))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.appTitle).foregroundStyle(Color.appInk)
                Text([profile.position, profile.teamName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkSoft)
                HStack(spacing: 10) {
                    if let nationality = profile.nationality {
                        HStack(spacing: 4) {
                            WCBadge(url: profile.flagURL, size: 14)
                            Text(nationality)
                        }
                    }
                    if let age = profile.age { Text("Age \(age)") }
                    if let height = profile.height { Text(height) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    // MARK: Season

    private func totals(_ profile: SoccerPlayerProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: .appSpace3) {
                totalTile("Goals", profile.total("totalGoals"))
                totalTile("Assists", profile.total("goalAssists"))
                totalTile("Shots", profile.total("totalShots"))
                totalTile("Starts", profile.total("starts"))
            }
            Text("Across every competition below")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, .appSpace2)
        }
    }

    private func totalTile(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.appInk)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: .appSpace3)
        .accessibilityElement(children: .combine)
    }

    /// Stat columns for the per-competition table.
    private static let seasonColumns: [(name: String, label: String)] = [
        ("starts", "ST"), ("totalGoals", "G"), ("goalAssists", "A"), ("shotsOnTarget", "SOT"), ("yellowCards", "YC"),
    ]

    private func seasonsCard(_ seasons: [SoccerPlayerSeason]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // ESPN's current season per competition: for an international that
            // includes the summer's tournament and friendlies, so not "this season".
            Text("BY COMPETITION").appEyebrow().foregroundStyle(Color.app(.soccer))
            HStack {
                Text("Competition").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.seasonColumns, id: \.name) { column in
                    Text(column.label).frame(width: 32)
                }
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            ForEach(seasons) { season in
                HStack {
                    Text(Self.competitionName(season.competition))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Self.seasonColumns, id: \.name) { column in
                        Text(season.stats.first { $0.name == column.name }?.displayValue ?? "–")
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 32)
                    }
                }
            }
        }
        .appCard()
    }

    /// "2026-27 English Premier League" → "English Premier League".
    static func competitionName(_ name: String) -> String {
        let words = name.split(separator: " ", maxSplits: 1)
        guard words.count == 2, words[0].first?.isNumber == true else { return name }
        return String(words[1])
    }

    // MARK: Recent matches

    private func recentCard(_ matches: [SoccerPlayerMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST \(matches.count) MATCHES").appEyebrow().foregroundStyle(Color.app(.soccer))
            ForEach(matches) { match in
                recentRow(match)
            }
        }
        .appCard()
    }

    private func recentRow(_ match: SoccerPlayerMatch) -> some View {
        HStack(spacing: 10) {
            if let result = match.result {
                Text(result.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(SoccerLeagueTableView.color(for: result), in: RoundedRectangle(cornerRadius: 5))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(match.isHome ? "vs" : "at") \(match.opponentName)")
                    .font(.subheadline)
                    .lineLimit(1)
                Text([match.date?.formatted(.dateTime.month(.abbreviated).day()), match.competition, match.appearance]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if match.stat("totalGoals") > 0 { Text(String(repeating: "⚽︎", count: match.stat("totalGoals"))) }
                if match.stat("goalAssists") > 0 { Text("🅰︎\(match.stat("goalAssists") > 1 ? "×\(match.stat("goalAssists"))" : "")") }
                if match.stat("redCards") > 0 { Text("🟥") } else if match.stat("yellowCards") > 0 { Text("🟨") }
            }
            .font(.caption)
            if let goalsFor = match.goalsFor, let goalsAgainst = match.goalsAgainst {
                Text("\(goalsFor)–\(goalsAgainst)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }

    private func nextCard(_ next: SoccerPlayerFixture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT MATCH").appEyebrow().foregroundStyle(Color.app(.soccer))
            Text(next.name).font(.subheadline).fontWeight(.medium)
            Text([next.date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()),
                  next.competition].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
