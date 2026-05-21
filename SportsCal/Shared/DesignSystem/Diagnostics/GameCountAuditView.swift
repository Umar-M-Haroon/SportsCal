//
//  GameCountAuditView.swift
//  SportsCal — Diagnostics
//
//  Settings → "Game count audit" diagnostic screen. Shows every count
//  source side-by-side so you can pinpoint which view is dropping games
//  before users do.
//

import SwiftUI
import SportsCalModel

struct GameCountAuditView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var snapshot: GameCountSnapshot {
        GameCountAudit.snapshot(for: selectedDate, viewModel: viewModel, storage: storage)
    }

    var body: some View {
        let snap = snapshot
        Form {
            Section {
                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
            }

            Section("Day-bounded — should match") {
                if snap.hasDivergence {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appLive)
                        Text("Counts diverge — a screen is dropping games for \(snap.dateLabel).")
                            .font(.appCallout)
                            .foregroundStyle(Color.appLive)
                    }
                }
                rowFor("Modern Today", count: snap.modernTodayCount, divergent: snap.hasDivergence)
                rowFor("Classic / Ambient Today", count: snap.classicTodayCount, divergent: snap.hasDivergence)
                rowFor("totalGames on date", count: snap.totalGamesOnDate, divergent: false)
                rowFor("filteredGames on date", count: snap.filteredGamesOnDate, divergent: false)
            }

            Section("All dates") {
                rowFor("totalGames", count: snap.totalGamesAllDates)
                rowFor("filteredGames", count: snap.filteredGamesAllDates)
                rowFor("calendarGames", count: snap.calendarGamesAllDates)
                rowFor("liveEvents", count: snap.liveEventsCount)
                rowFor("liveEventsWithTeams", count: snap.liveEventsWithTeamsCount)
            }

            Section("Browse — per sport (all dates)") {
                let totalSum = snap.browsePerSport.map(\.total).reduce(0, +)
                let liveSum = snap.browsePerSport.map(\.live).reduce(0, +)
                ForEach(snap.browsePerSport, id: \.sport) { tuple in
                    HStack {
                        Image(systemName: tuple.sport.systemImage)
                            .foregroundStyle(Color.app(tuple.sport))
                        Text(tuple.sport.displayName)
                            .font(.appCallout)
                        Spacer()
                        if tuple.live > 0 {
                            Text("\(tuple.live) LIVE")
                                .font(.appFootnote)
                                .tracking(1)
                                .foregroundStyle(Color.app(tuple.sport))
                        }
                        Text("\(tuple.total)")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
                HStack {
                    Text("Sum")
                        .font(.appHeadline)
                    Spacer()
                    if liveSum > 0 {
                        Text("\(liveSum) LIVE")
                            .font(.appFootnote).tracking(1)
                            .foregroundStyle(Color.appLive)
                    }
                    Text("\(totalSum)")
                        .font(.system(.body, design: .monospaced).weight(.heavy))
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }

            Section("Why each row") {
                ForEach(snap.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.label)
                                .font(.appCallout)
                            Spacer()
                            Text("\(row.count)")
                                .font(.system(.callout, design: .monospaced).weight(.bold))
                                .monospacedDigit()
                        }
                        Text(row.source)
                            .font(.appCaption)
                            .foregroundStyle(Color.appInkSoft)
                    }
                }
            }
        }
    }

    private func rowFor(_ label: String, count: Int, divergent: Bool = false) -> some View {
        HStack {
            Text(label).font(.appCallout)
            Spacer()
            Text("\(count)")
                .font(.system(.body, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(divergent ? Color.appLive : Color.appInk)
        }
    }
}
