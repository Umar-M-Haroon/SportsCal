//
//  EFRemixComponents.swift
//  SportsCal (iOS)
//
//  Small primitives shared by the EF Remix screens: the cross-fading
//  Rotator that cycles plays/leaders/context, a Path-based sparkline, the
//  leading sport stripe modifier, and the gold ring for favorites.
//

import SwiftUI
import SportsCalModel

// MARK: - EFRotator

/// Cycles `items` every `interval` seconds with a soft cross-fade. Pauses
/// when the scene moves to background — the design intentionally reads as
/// "ambient", but no point spending a timer cycle when the screen isn't
/// visible.
struct EFRotator<Item, Content: View>: View {
    let items: [Item]
    let interval: TimeInterval
    @ViewBuilder let render: (Item, Int) -> Content

    @State private var index: Int = 0
    @State private var timer: Timer?
    @Environment(\.scenePhase) private var scenePhase

    init(items: [Item], interval: TimeInterval = 2.4,
         @ViewBuilder render: @escaping (Item, Int) -> Content) {
        self.items = items
        self.interval = interval
        self.render = render
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                let safeIndex = min(index, items.count - 1)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        render(item, idx)
                            .opacity(idx == safeIndex ? 1 : 0)
                            .offset(y: idx == safeIndex ? 0 : 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.38), value: safeIndex)
            }
        }
        .onAppear { restartTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { restartTimer() }
            else { stopTimer() }
        }
        .onChange(of: items.count) { _, _ in
            index = 0
            restartTimer()
        }
    }

    private func restartTimer() {
        stopTimer()
        guard items.count > 1 else { return }
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                index = (index + 1) % max(items.count, 1)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - EFSportGlyph

/// Small sport icon. Re-uses `SportType.systemImage` (already curated for
/// every sport in `SportsTint.swift`) rather than recreating the JSX's
/// hand-drawn SVGs — the SF Symbols read better at small sizes anyway.
struct EFSportGlyph: View {
    let sport: SportType
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: sport.systemImage)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
            .frame(width: size + 2, height: size + 2)
    }
}

// MARK: - EFSpark

/// Tiny sparkline polyline. Mirrors the JSX `Spark` — auto-scales to the
/// supplied frame, no axis chrome.
struct EFSpark: View {
    let data: [Double]
    let color: Color
    let width: CGFloat
    let height: CGFloat

    init(data: [Double], color: Color, width: CGFloat = 60, height: CGFloat = 14) {
        self.data = data
        self.color = color
        self.width = width
        self.height = height
    }

    var body: some View {
        Canvas { ctx, size in
            guard data.count >= 2 else { return }
            let max = data.max() ?? 1
            let min = data.min() ?? 0
            let range = (max - min) == 0 ? 1 : (max - min)
            var path = Path()
            for (i, v) in data.enumerated() {
                let x = (Double(i) / Double(data.count - 1)) * (size.width - 2) + 1
                let y = size.height - 1 - ((v - min) / range) * (size.height - 2)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// MARK: - EFCardStripe

/// Leading colored bar — the visual signature of the EF Remix system,
/// applied to almost every card / row.
struct EFCardStripe: ViewModifier {
    let color: Color
    let width: CGFloat
    let cornerRadius: CGFloat

    init(color: Color, width: CGFloat = 3, cornerRadius: CGFloat = 8) {
        self.color = color
        self.width = width
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: width)
                .clipShape(
                    .rect(topLeadingRadius: cornerRadius,
                          bottomLeadingRadius: cornerRadius,
                          bottomTrailingRadius: 0,
                          topTrailingRadius: 0)
                )
        }
    }
}

extension View {
    func efCardStripe(_ color: Color, width: CGFloat = 3, cornerRadius: CGFloat = 8) -> some View {
        modifier(EFCardStripe(color: color, width: width, cornerRadius: cornerRadius))
    }

    /// Gold favorite ring — the design's "★ leverage" indicator at the
    /// outer edge of any card/row.
    func efFavoriteRing(active: Bool, mode: EFMode, cornerRadius: CGFloat = 8) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(EFTheme.star(mode), lineWidth: 1)
            }
        }
    }
}

// MARK: - EFLivePill

/// "● n LIVE" indicator used on day/browse headers.
struct EFLivePill: View {
    let count: Int
    let mode: EFMode

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(EFTheme.live(mode))
                .frame(width: 6, height: 6)
            Text("\(count) LIVE")
                .font(EFFont.mono(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(EFTheme.live(mode))
        }
    }
}

// MARK: - Eyebrow + headline

/// `MON · MMM dd · BUSY DAY` mono caplet over a hand-written headline.
struct EFEyebrowHeadline: View {
    let eyebrow: String
    let headline: String
    let mode: EFMode
    var headlineSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(EFFont.mono(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(EFTheme.faint(mode))
            Text(headline)
                .font(EFFont.hand(headlineSize, relativeTo: .largeTitle))
                .foregroundStyle(EFTheme.ink(mode))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
