//
//  AmbientStyle.swift
//  SportsCal
//
//  Shared palette, typography, and small composable primitives for the
//  Ambient (Direction E) theme — dark, airport-departures-board aesthetic.
//

import SwiftUI
import SportsCalModel

enum AmbientPalette {
    static let bg        = Color(red: 0.051, green: 0.051, blue: 0.051)    // #0D0D0D
    static let ink       = Color(red: 0.961, green: 0.957, blue: 0.933)    // #F5F4EE
    static let muted     = Color.white.opacity(0.5)
    static let faint     = Color.white.opacity(0.1)
    static let divider   = Color.white.opacity(0.06)
    static let highlight = Color(red: 1.0,   green: 0.949, blue: 0.541)    // #FFF28A
    static let live      = Color(red: 1.0,   green: 0.353, blue: 0.290)    // #FF5A4A
    static let tileStroke = Color.white.opacity(0.12)
}

// MARK: - Typography helpers

extension Font {
    static func ambientMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func ambientDisplay(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Section label (UPPERCASE_LETTERSPACED · MUTED)

struct AmbientSectionLabel: View {
    let text: String
    var color: Color = AmbientPalette.muted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.ambientMono(size, weight: .regular))
            .tracking(2)
            .foregroundStyle(color)
    }
}

// MARK: - Departure row — the single airport-board row primitive

struct AmbientDepartureRow: View {
    let time: String           // "17:30" or "LIVE" or "SOON"
    let sport: SportType?
    let matchText: String      // "ARS — MCI" or "LAL 98 — 104 BOS"
    let statusText: String     // "4Q · 4:22" / "FINAL" / "TOP 7" / "SOON"
    let isLive: Bool
    let isFavorite: Bool
    let isFinal: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.ambientMono(12))
                .foregroundStyle(AmbientPalette.ink)
                .frame(width: 48, alignment: .leading)

            if let sport {
                Image(systemName: sport.systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(isLive ? AmbientPalette.highlight : AmbientPalette.ink.opacity(0.8))
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            Text(matchText)
                .font(.ambientDisplay(14, weight: .semibold))
                .foregroundStyle(isFinal ? AmbientPalette.muted : AmbientPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AmbientPalette.highlight)
            }

            Text(statusText.uppercased())
                .font(.ambientMono(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(statusColor)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AmbientPalette.divider)
                .frame(height: 1)
        }
    }

    private var statusColor: Color {
        if isLive { return AmbientPalette.live }
        if isFinal { return AmbientPalette.muted }
        return AmbientPalette.ink.opacity(0.65)
    }
}

// MARK: - 2×2 stat tile

struct AmbientTile: View {
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AmbientSectionLabel(text: label, size: 8)
            Text(value)
                .font(.ambientDisplay(20, weight: .bold))
                .foregroundStyle(AmbientPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub)
                    .font(.ambientDisplay(10, weight: .regular))
                    .foregroundStyle(AmbientPalette.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AmbientPalette.tileStroke, lineWidth: 1)
        )
    }
}

// MARK: - Ambient header (top-of-screen eyebrow + big title)

struct AmbientHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                AmbientSectionLabel(text: eyebrow, size: 11)
                Text(title)
                    .font(.ambientDisplay(28, weight: .bold))
                    .foregroundStyle(AmbientPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - Live pill

struct AmbientLivePill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AmbientPalette.live)
                .frame(width: 6, height: 6)
            Text("\(count) LIVE")
                .font(.ambientMono(11, weight: .bold))
                .tracking(1)
                .foregroundStyle(AmbientPalette.live)
        }
    }
}

// MARK: - Match text helpers

enum AmbientFormat {
    /// "AWAY 98 — 104 HOME" for live/final, "AWAY — HOME" for upcoming.
    static func matchText(game: Game, away: Team?, home: Team?) -> String {
        let awayAbbr = abbreviation(team: away, fallback: game.strAwayTeam)
        let homeAbbr = abbreviation(team: home, fallback: game.strHomeTeam)
        if let a = Int(game.intAwayScore ?? ""),
           let h = Int(game.intHomeScore ?? "") {
            return "\(awayAbbr) \(a) — \(h) \(homeAbbr)"
        }
        return "\(awayAbbr) — \(homeAbbr)"
    }

    /// "17:30" for a scheduled game, short fallback for unknown.
    static func timeText(for date: Date?, isLive: Bool, isFinal: Bool) -> String {
        if isLive { return "LIVE" }
        if isFinal { return "FINAL" }
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func abbreviation(team: Team?, fallback: String) -> String {
        if let abbr = team?.strTeamShort, !abbr.isEmpty { return abbr.uppercased() }
        // Collapse "Los Angeles Lakers" → "LAL" if nothing better is available.
        let words = fallback.split(separator: " ")
        if words.count >= 2 {
            let initials = words.prefix(3).compactMap { $0.first }
            return String(initials).uppercased()
        }
        return fallback.uppercased()
    }
}
