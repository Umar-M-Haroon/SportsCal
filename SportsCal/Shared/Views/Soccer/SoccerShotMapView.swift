//
//  SoccerShotMapView.swift
//  SportsCal
//
//  Every located shot on one landscape pitch, FotMob-style: the away side
//  shooting at the left goal and the home side at the right (matching the
//  away-left / home-right layout of the rest of the detail screen). Dot size is
//  the shot's estimated xG; goals are filled and ringed, saved shots filled,
//  misses/blocks hollow. Tap a dot for who, when and how good a chance it was.
//

import SwiftUI
import SportsCalModel

struct SoccerShotMapView: View {
    let shots: [SoccerShot]
    let homeName: String
    let awayName: String
    let homeColor: Color
    let awayColor: Color

    @State private var selectedID: String?

    /// Length over width of a 105 × 68 m pitch.
    private static let aspectRatio: CGFloat = 105 / 68

    private var selected: SoccerShot? { shots.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow

            GeometryReader { geo in
                ZStack {
                    PitchMarkings(horizontal: true)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    // Biggest chances underneath, so small dots stay tappable.
                    ForEach(shots.sorted { $0.xG > $1.xG }) { shot in
                        dot(shot)
                            .position(point(for: shot, in: geo.size))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedID = nil }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .background(PitchMarkings.turf, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Shot map")

            if let selected {
                selectedDetail(selected)
                    .transition(.opacity)
            } else {
                legend
            }
        }
        .animation(.snappy, value: selectedID)
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(alignment: .top) {
            teamSummary(side: .away, name: awayName, color: awayColor, alignment: .leading)
            Spacer()
            teamSummary(side: .home, name: homeName, color: homeColor, alignment: .trailing)
        }
    }

    private func teamSummary(side: BracketSide, name: String, color: Color, alignment: HorizontalAlignment) -> some View {
        let teamShots = shots.filter { $0.side == side }
        let xG = teamShots.reduce(0) { $0 + $1.xG }
        let onTarget = teamShots.filter { $0.outcome.isOnTarget }.count
        return VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 6) {
                if alignment == .leading { Circle().fill(color).frame(width: 8, height: 8) }
                Text(name).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                if alignment == .trailing { Circle().fill(color).frame(width: 8, height: 8) }
            }
            Text("\(String(format: "%.2f", xG)) xG · \(teamShots.count) shots · \(onTarget) on target")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: Dots

    /// Home shoots at the right goal, so its left (y > 50) is the top of the screen;
    /// away shoots at the left goal, mirrored.
    private func point(for shot: SoccerShot, in size: CGSize) -> CGPoint {
        let x = shot.x / 100, y = shot.y / 100
        if shot.side == .home {
            return CGPoint(x: size.width * x, y: size.height * (1 - y))
        }
        return CGPoint(x: size.width * (1 - x), y: size.height * y)
    }

    private func diameter(_ shot: SoccerShot) -> CGFloat {
        8 + 26 * CGFloat(shot.xG.squareRoot())
    }

    private func dot(_ shot: SoccerShot) -> some View {
        let color = shot.side == .home ? homeColor : awayColor
        let size = diameter(shot)
        let isSelected = shot.id == selectedID
        return ZStack {
            switch shot.outcome {
            case .goal:
                Circle().fill(color)
                Circle().stroke(.white, lineWidth: 2)
                Image(systemName: "soccerball")
                    .font(.system(size: max(size * 0.45, 7)))
                    .foregroundStyle(.white)
            case .saved:
                Circle().fill(color.opacity(0.85))
                Circle().stroke(.white.opacity(0.7), lineWidth: 1)
            case .missed, .blocked, .woodwork:
                Circle().fill(color.opacity(0.2))
                Circle().stroke(color, lineWidth: 1.5)
                Circle().stroke(.white.opacity(0.4), lineWidth: 0.5)
            }
            if isSelected {
                Circle().stroke(.yellow, lineWidth: 2.5).padding(-4)
            }
        }
        .frame(width: size, height: size)
        // A comfortable tap target even for the smallest chances.
        .frame(width: max(size, 24), height: max(size, 24))
        .contentShape(Circle())
        .onTapGesture { selectedID = isSelected ? nil : shot.id }
        .accessibilityElement()
        .accessibilityLabel(Self.description(of: shot))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Detail and legend

    private func selectedDetail(_ shot: SoccerShot) -> some View {
        HStack(spacing: 10) {
            Text(shot.clock)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(shot.playerName ?? "Unknown player")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(Self.outcomeText(shot.outcome)) · \(Self.howText(shot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.2f", shot.xG))
                    .font(.headline)
                    .monospacedDigit()
                Text("xG (est.)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Goal") { Circle().fill(Color.primary).overlay(Circle().stroke(.white, lineWidth: 1.5)) }
            legendItem("On target") { Circle().fill(Color.primary.opacity(0.7)) }
            legendItem("Off target") { Circle().stroke(Color.primary, lineWidth: 1.5) }
            Spacer()
            Text("Size = xG (est.)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func legendItem<Mark: View>(_ label: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 4) {
            mark().frame(width: 9, height: 9)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private static func outcomeText(_ outcome: SoccerShotOutcome) -> String {
        switch outcome {
        case .goal: return "Goal"
        case .saved: return "Saved"
        case .missed: return "Missed"
        case .blocked: return "Blocked"
        case .woodwork: return "Hit the woodwork"
        }
    }

    private static func howText(_ shot: SoccerShot) -> String {
        let body: String
        switch shot.bodyPart {
        case .rightFoot: body = "Right foot"
        case .leftFoot: body = "Left foot"
        case .head: body = "Header"
        case .other: body = "Shot"
        }
        switch shot.situation {
        case .penalty: return "Penalty"
        case .directFreeKick: return "\(body), direct free kick"
        case .setPiece: return "\(body), from a set piece"
        case .fastBreak: return "\(body), fast break"
        case .openPlay: return body
        }
    }

    private static func description(of shot: SoccerShot) -> String {
        let who = shot.playerName ?? "Unknown player"
        return "\(shot.clock) \(who), \(howText(shot)), \(outcomeText(shot.outcome)), expected goals \(String(format: "%.2f", shot.xG))"
    }
}
