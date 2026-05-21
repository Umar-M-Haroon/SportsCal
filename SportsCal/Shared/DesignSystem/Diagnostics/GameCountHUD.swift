//
//  GameCountHUD.swift
//  SportsCal — Diagnostics
//
//  Floating debug overlay that surfaces game-count divergence between
//  views. Toggleable via Settings → Developer → "Game count HUD".
//
//  Compact pill in the bottom-right shows the day-bounded counts in the
//  format "M:12 C:12 T:12". Pill turns red on divergence. Tap expands to
//  the full audit table.
//

import SwiftUI
import SportsCalModel

struct GameCountHUD: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage

    @State private var expanded = false
    @State private var showFullAudit = false

    private var snapshot: GameCountSnapshot {
        GameCountAudit.snapshot(
            for: Date(),
            viewModel: viewModel,
            storage: storage
        )
    }

    var body: some View {
        let snap = snapshot
        let diverges = snap.hasDivergence

        VStack(alignment: .trailing, spacing: 6) {
            if expanded {
                expandedPanel(for: snap)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                pill(for: snap, diverges: diverges)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(true)
        .sheet(isPresented: $showFullAudit) {
            NavigationStack {
                GameCountAuditView()
                    .environment(viewModel)
                    .environment(storage)
                    .navigationTitle("Game count audit")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showFullAudit = false }
                        }
                    }
                    #endif
            }
        }
    }

    private func pill(for snap: GameCountSnapshot, diverges: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(diverges ? Color.appLive : Color.appPositive)
                .frame(width: 6, height: 6)
            Text("M:\(snap.modernTodayCount) C:\(snap.classicTodayCount) T:\(snap.totalGamesOnDate)")
                .font(.system(size: 11, design: .monospaced).weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(diverges ? Color.appLive.opacity(0.6) : Color.appDivider,
                              lineWidth: 1)
        )
        .foregroundStyle(diverges ? Color.appLive : Color.appInk)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Game count: Modern \(snap.modernTodayCount), Classic \(snap.classicTodayCount), Total \(snap.totalGamesOnDate). \(diverges ? "Divergence detected." : "Counts match.")"))
    }

    private func expandedPanel(for snap: GameCountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY · \(snap.dateLabel)").appEyebrow()
            statRow("Modern", value: snap.modernTodayCount, divergent: snap.dayBoundedCounts.contains(snap.modernTodayCount) && Set(snap.dayBoundedCounts).count > 1)
            statRow("Classic / Ambient", value: snap.classicTodayCount, divergent: snap.dayBoundedCounts.contains(snap.classicTodayCount) && Set(snap.dayBoundedCounts).count > 1)
            statRow("totalGames", value: snap.totalGamesOnDate, divergent: false)
            statRow("filteredGames", value: snap.filteredGamesOnDate, divergent: false)
            Divider().padding(.vertical, 2)
            statRow("Live", value: snap.liveEventsCount, divergent: false)
            statRow("All-dates total", value: snap.totalGamesAllDates, divergent: false)

            Button {
                showFullAudit = true
                expanded = false
            } label: {
                Text("Open full audit")
                    .font(.system(size: 11, design: .monospaced).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.appAlt))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(10)
        .frame(width: 220)
        .background(
            RoundedRectangle.appShape(.appRadiusMD)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle.appShape(.appRadiusMD)
                .strokeBorder(Color.appDivider, lineWidth: 1)
        )
    }

    private func statRow(_ label: String, value: Int, divergent: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.appInkSoft)
            Spacer()
            Text("\(value)")
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .foregroundStyle(divergent ? Color.appLive : Color.appInk)
        }
    }
}
