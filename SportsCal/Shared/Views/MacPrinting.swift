//
//  MacPrinting.swift
//  SportsCal
//
//  Shared print pipeline for File → Print Schedule… (⌘P). Used by both the
//  Classic board (DayPage) and the EFRemix window (ModernMacWindow).
//

#if os(macOS)
import SwiftUI
import AppKit
import SportsCalModel

/// Runs a print operation for one day's schedule. NSPrintOperation paginates
/// by the host view's height, so the hosting view is sized to full content
/// height before the operation starts.
@MainActor
func runSchedulePrint(title: String, games: [Game]) {
    let printable = SchedulePrintView(title: title, games: games)
    let hosting = NSHostingView(rootView: printable)
    let height = max(240, CGFloat(games.count) * 26 + 140)
    hosting.frame = NSRect(x: 0, y: 0, width: 540, height: height)
    let operation = NSPrintOperation(view: hosting)
    operation.printInfo.horizontalPagination = .fit
    operation.run()
}

/// Plain black-on-white schedule used only for printing (⌘P / File → Print).
struct SchedulePrintView: View {
    let title: String
    let games: [Game]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scoreline")
                .font(.title.bold())
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider()
            if games.isEmpty {
                Text("No games scheduled.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(games, id: \.id) { game in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(game.standardDate?.formatted(date: .omitted, time: .shortened) ?? "—")
                            .frame(width: 80, alignment: .leading)
                            .monospacedDigit()
                        Text("\(game.strAwayTeam) @ \(game.strHomeTeam)")
                        Spacer(minLength: 0)
                        if let away = game.intAwayScore, let home = game.intHomeScore,
                           !away.isEmpty, !home.isEmpty {
                            Text("\(away)–\(home)")
                                .monospacedDigit()
                        }
                    }
                    .font(.body)
                }
            }
        }
        .padding(28)
        .frame(width: 540, alignment: .leading)
        .foregroundStyle(.black)
        .background(Color.white)
    }
}
#endif
