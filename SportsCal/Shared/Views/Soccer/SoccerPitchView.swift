//
//  SoccerPitchView.swift
//  SportsCal
//
//  Both starting XIs on one vertical pitch, FotMob-style: the away side in the
//  top half attacking down, the home side in the bottom half attacking up. Each
//  player sits where their formation puts them (see `SoccerFormationLayout`),
//  with goals, cards and substitutions marked; tap a player for their match stats.
//

import SwiftUI
import SportsCalModel

struct SoccerPitchView: View {
    let home: SoccerLineup
    let away: SoccerLineup
    let homeColor: Color
    let awayColor: Color
    /// Opens a player's profile from their stats popover. The popover isn't part of
    /// the navigation stack, so the owner does the push.
    var onOpenProfile: ((SoccerLineupPlayer) -> Void)?

    @State private var selected: SoccerLineupPlayer?

    /// Width over length of a 68 × 105 m pitch.
    private static let aspectRatio: CGFloat = 68 / 105

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                PitchMarkings()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)

                if let awayPlacements = SoccerFormationLayout.place(away) {
                    ForEach(awayPlacements, id: \.player.id) { placement in
                        chip(placement.player, color: awayColor)
                            .position(point(for: placement, isHome: false, in: size))
                    }
                }
                if let homePlacements = SoccerFormationLayout.place(home) {
                    ForEach(homePlacements, id: \.player.id) { placement in
                        chip(placement.player, color: homeColor)
                            .position(point(for: placement, isHome: true, in: size))
                    }
                }

                formationLabel(away, alignment: .topLeading)
                formationLabel(home, alignment: .bottomLeading)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .background(PitchMarkings.turf, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Starting lineups")
    }

    /// Home attacks up, so its right touchline is on the right of the screen; away
    /// attacks down, mirrored.
    private func point(for placement: SoccerFormationLayout.Placement, isHome: Bool, in size: CGSize) -> CGPoint {
        let halfDepth = placement.depth * size.height / 2
        if isHome {
            return CGPoint(x: size.width * (1 - placement.across), y: size.height - halfDepth)
        }
        return CGPoint(x: size.width * placement.across, y: halfDepth)
    }

    private func formationLabel(_ lineup: SoccerLineup, alignment: Alignment) -> some View {
        Text(lineup.formation ?? "")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.8))
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .allowsHitTesting(false)
    }

    // MARK: Player chip

    private func chip(_ player: SoccerLineupPlayer, color: Color) -> some View {
        Button {
            selected = player
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    Text(player.jersey ?? "")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color.isLight ? Color.black : Color.white)
                        .monospacedDigit()
                }
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) { goalBadge(player) }
                .overlay(alignment: .topLeading) { cardBadge(player) }
                .overlay(alignment: .bottomTrailing) { subBadge(player) }

                Text(Self.pitchName(player))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 74)
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(player))
        .popover(isPresented: Binding(
            get: { selected?.id == player.id },
            set: { if !$0 { selected = nil } }
        )) {
            SoccerPlayerStatsCard(
                player: player,
                onOpenProfile: player.athleteID == nil ? nil : onOpenProfile.map { open in
                    {
                        selected = nil
                        open(player)
                    }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func goalBadge(_ player: SoccerLineupPlayer) -> some View {
        let goals = player.stat("totalGoals")
        if goals > 0 {
            Text(goals > 1 ? "⚽︎\(goals)" : "⚽︎")
                .font(.system(size: 9))
                .padding(1)
                .background(.white, in: Capsule())
                .offset(x: 8, y: -5)
        }
    }

    @ViewBuilder
    private func cardBadge(_ player: SoccerLineupPlayer) -> some View {
        if player.stat("redCards") > 0 || player.stat("yellowCards") > 0 {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(player.stat("redCards") > 0 ? Color.red : Color.yellow)
                .frame(width: 7, height: 10)
                .offset(x: -4, y: -3)
        }
    }

    @ViewBuilder
    private func subBadge(_ player: SoccerLineupPlayer) -> some View {
        if player.subbedOut {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white, .red)
                .offset(x: 5, y: 4)
        }
    }

    /// "V. van Dijk" → "van Dijk"; otherwise the last word of the full name.
    static func pitchName(_ player: SoccerLineupPlayer) -> String {
        if let short = player.shortName, let range = short.range(of: ". ") {
            return String(short[range.upperBound...])
        }
        return player.name.split(separator: " ").last.map(String.init) ?? player.name
    }

    private static func accessibilityLabel(_ player: SoccerLineupPlayer) -> String {
        var parts = [player.name]
        if let jersey = player.jersey { parts.append("number \(jersey)") }
        if let position = player.positionName { parts.append(position) }
        let goals = player.stat("totalGoals")
        if goals > 0 { parts.append(goals == 1 ? "scored" : "scored \(goals)") }
        if player.stat("redCards") > 0 { parts.append("sent off") }
        else if player.stat("yellowCards") > 0 { parts.append("booked") }
        if player.subbedOut { parts.append("substituted") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Player stats popover

private struct SoccerPlayerStatsCard: View {
    let player: SoccerLineupPlayer
    var onOpenProfile: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let jersey = player.jersey {
                    Text(jersey)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.name).font(.headline)
                    if let position = player.positionName {
                        Text(position).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if player.stats.isEmpty {
                Text("No stats yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(player.stats, id: \.name) { stat in
                        GridRow {
                            Text(stat.displayName ?? stat.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(stat.displayValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
            if let onOpenProfile {
                Button("Player profile", systemImage: "person.crop.circle", action: onOpenProfile)
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}

// MARK: - Pitch markings

/// The lines of a pitch, scaled to the view (proportions of a 68 × 105 m pitch).
/// Vertical by default; `horizontal` lays the goals at the left and right.
struct PitchMarkings: Shape {
    var horizontal = false

    /// The grass the markings sit on.
    static let turf = LinearGradient(
        colors: [Color(red: 0.13, green: 0.42, blue: 0.24), Color(red: 0.10, green: 0.35, blue: 0.20)],
        startPoint: .top, endPoint: .bottom
    )

    func path(in rect: CGRect) -> Path {
        guard horizontal else { return verticalPath(in: rect) }
        // Draw it upright in a swapped rect, then turn it a quarter: (x, y) → (y, height − x).
        let upright = verticalPath(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width))
        let quarterTurn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.minX, ty: rect.minY + rect.height)
        return upright.applying(quarterTurn)
    }

    private func verticalPath(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 6, dy: 6)
        let w = inset.width, h = inset.height
        let mx = w / 68, my = h / 105
        var path = Path()

        path.addRect(inset)
        // Halfway line and centre circle.
        path.move(to: CGPoint(x: inset.minX, y: inset.midY))
        path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
        let circle = 9.15 * mx
        path.addEllipse(in: CGRect(x: inset.midX - circle, y: inset.midY - circle * my / mx,
                                   width: circle * 2, height: circle * 2 * my / mx))

        for top in [true, false] {
            // Penalty area (40.3 × 16.5 m) and six-yard box (18.3 × 5.5 m).
            for (boxWidth, boxDepth) in [(40.3, 16.5), (18.3, 5.5)] {
                let bw = boxWidth * mx, bd = boxDepth * my
                let y = top ? inset.minY : inset.maxY - bd
                path.addRect(CGRect(x: inset.midX - bw / 2, y: y, width: bw, height: bd))
            }
            // Penalty spot.
            let spotY = top ? inset.minY + 11 * my : inset.maxY - 11 * my
            path.addEllipse(in: CGRect(x: inset.midX - 1.5, y: spotY - 1.5, width: 3, height: 3))
        }
        return path
    }
}

// MARK: - Contrast

private extension Color {
    /// Whether text on this colour should be dark. Uses resolved sRGB components,
    /// so it works for any colour, including the hex team colours.
    var isLight: Bool {
        let resolved = self.resolve(in: EnvironmentValues())
        let luminance = 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
        return luminance > 0.6
    }
}

#Preview {
    let place = { (slot: Int, position: String, name: String, starter: Bool) in
        SoccerLineupPlayer(name: name, jersey: "\(slot)", position: position, starter: starter, formationPlace: starter ? slot : nil)
    }
    let liverpool = SoccerLineup(teamName: "Liverpool", formation: "4-2-3-1", players: [
        place(1, "G", "Alisson Becker", true), place(2, "RB", "Jeremie Frimpong", true),
        place(3, "LB", "Milos Kerkez", true), place(4, "LM", "Ryan Gravenberch", true),
        place(5, "CD-R", "Jérémy Jacquet", true), place(6, "CD-L", "Virgil van Dijk", true),
        place(7, "AM-R", "Mohamed Salah", true), place(8, "RM", "Dominik Szoboszlai", true),
        place(9, "F", "Alexander Isak", true), place(10, "AM", "Florian Wirtz", true),
        place(11, "AM-L", "Cody Gakpo", true),
    ])
    let bournemouth = SoccerLineup(teamName: "Bournemouth", formation: "4-3-3", players: [
        place(1, "G", "Djordje Petrovic", true), place(2, "RB", "Alex Jiménez", true),
        place(3, "LB", "Adrien Truffert", true), place(4, "CM", "Alex Scott", true),
        place(5, "CD-R", "Marcos Senesi", true), place(6, "CD-L", "Bafodé Diakité", true),
        place(7, "RM", "Ryan Christie", true), place(8, "LM", "Tyler Adams", true),
        place(9, "F", "Evanilson", true), place(10, "RF", "Justin Kluivert", true),
        place(11, "LF", "David Brooks", true),
    ])
    return SoccerPitchView(home: bournemouth, away: liverpool, homeColor: .red, awayColor: Color(red: 0.78, green: 0.06, blue: 0.18))
        .padding()
}
