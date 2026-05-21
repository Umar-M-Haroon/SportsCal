//
//  Rotator.swift
//  SportsCal — Design System v1.0
//
//  Auto-advancing carousel with user controls. Cycles through `items` every
//  `interval` seconds with a fade transition. Supports:
//
//    • Tappable pagination dots (jump to a specific panel)
//    • Horizontal swipe to advance / retreat
//    • Pause when VoiceOver focuses the rotator (so the user can read at
//      their pace)
//    • Pause entirely under Reduce Motion (full pause, not just disable
//      the fade — Reduce Motion users typically also want longer reading
//      time, and the dots / swipe still allow manual navigation)
//    • Optional `pinnedIndex` — that index gets a longer dwell
//      (`interval × pinnedDwellMultiplier`) so a "live / priority" panel
//      can dominate the rotation without locking the others out
//
//  Implementation note: `.task(id: rotationTaskID)` restarts the auto-advance
//  timer on any state change (currentIndex / VO focus / Reduce Motion),
//  which makes user interactions automatically reset the dwell — no manual
//  pause-and-resume bookkeeping required.
//

import SwiftUI

public struct Rotator<Item, Content: View>: View {
    public let items: [Item]
    public let interval: TimeInterval
    public let pinnedIndex: Int?
    public let pinnedDwellMultiplier: Double
    @ViewBuilder public let content: (Item) -> Content

    @State private var currentIndex: Int
    @AccessibilityFocusState private var voFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        items: [Item],
        interval: TimeInterval = 5.0,
        pinnedIndex: Int? = nil,
        pinnedDwellMultiplier: Double = 2.0,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.interval = interval
        self.pinnedIndex = pinnedIndex
        self.pinnedDwellMultiplier = pinnedDwellMultiplier
        self.content = content
        // Seed the @State with the pinned index from the start. Defaulting
        // to 0 and then re-assigning in `.onAppear` caused a visible flicker
        // — the user saw the first panel for ~one frame before it jumped to
        // the pinned panel. Constructing State with the correct initial
        // value avoids that round-trip entirely.
        let initial = (pinnedIndex.flatMap { items.indices.contains($0) ? $0 : nil }) ?? 0
        self._currentIndex = State(initialValue: initial)
    }

    public var body: some View {
        ZStack {
            if items.indices.contains(currentIndex) {
                content(items[currentIndex])
                    .id(currentIndex)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.35), value: currentIndex)
        .gesture(swipeGesture)
        .overlay(alignment: .bottom) {
            dotStrip.offset(y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityFocused($voFocused)
        .task(id: rotationTaskID) {
            await runAutoAdvance()
        }
    }

    @ViewBuilder
    private var dotStrip: some View {
        if items.count > 1 {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { idx in
                    dotButton(idx: idx)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: currentIndex)
        }
    }

    /// Extracted from `dotStrip` so the ternaries don't tip SourceKit's
    /// type-checker into a timeout — chained modifiers + ternaries inside
    /// a `ForEach` add up faster than they look.
    private func dotButton(idx: Int) -> some View {
        let isSelected = idx == currentIndex
        return Button {
            currentIndex = idx
        } label: {
            Capsule()
                .fill(Color.appInk)
                .opacity(isSelected ? 0.85 : 0.25)
                .frame(width: isSelected ? 16 : 6, height: 4)
                .padding(.vertical, 10)  // expand the tap target — capsule is only 4pt tall
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Page \(idx + 1) of \(items.count)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Horizontal swipe — left advances, right retreats. `minimumDistance: 30`
    /// avoids stealing taps from the dot row underneath.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) >= 30 else { return }
                if dx > 0 { retreat() } else { advance() }
            }
    }

    /// Restart key for the auto-advance task. Any field change (user
    /// navigates manually, VO focuses, Reduce Motion flips) restarts the
    /// task with a fresh dwell — no separate pause/resume timestamp needed.
    private var rotationTaskID: String {
        "\(currentIndex)-\(voFocused)-\(reduceMotion)-\(pinnedIndex ?? -1)-\(items.count)"
    }

    /// One sleep + one advance per task lifetime. The enclosing `.task(id:)`
    /// restarts this on every state change, so the loop is naturally driven
    /// by SwiftUI rather than a long-running iteration.
    private func runAutoAdvance() async {
        // Accessibility constraints fully disable auto-rotation. Users can
        // still drive via dots / swipe.
        guard !reduceMotion, !voFocused, items.count > 1 else { return }
        try? await Task.sleep(for: .seconds(currentDwell()))
        guard !Task.isCancelled else { return }
        advance()
    }

    private func currentDwell() -> TimeInterval {
        if let pinnedIndex, currentIndex == pinnedIndex {
            return interval * pinnedDwellMultiplier
        }
        return interval
    }

    private func advance() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
    }

    private func retreat() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
    }
}
