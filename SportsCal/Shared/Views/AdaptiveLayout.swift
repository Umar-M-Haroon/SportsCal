//
//  AdaptiveLayout.swift
//  SportsCal
//
//  Layout decisions driven by the space a view actually gets, not by device or
//  size class. The iPhone Duo's inner display reports a regular size class in
//  both orientations at only 669–951pt, so "regular" no longer means "iPad".
//  Also home to the fold-aware detail layout used by game detail.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Applies a transform inline, for modifiers that need a helper function
    /// (e.g. `#available` branches that a toolbar builder can't express).
    func apply<V: View>(@ViewBuilder _ transform: (Self) -> V) -> V {
        transform(self)
    }

    /// Caps content at a comfortable reading width and centers it. Detail screens
    /// were tuned for phone widths; on a 951pt foldable or an iPad they'd stretch.
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// `readableWidth` for a List or ScrollView: insets its content to the same
    /// centered measure while the background and scroll area stay full width.
    func readableScrollWidth(_ maxWidth: CGFloat = 700) -> some View {
        modifier(ReadableScrollWidth(maxWidth: maxWidth))
    }
}

private struct ReadableScrollWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

// MARK: - Layout rules

/// How the Games tab lays out for a given width (iOS).
enum GamesLayout: Equatable {
    /// One scrolling list. iPhone, the Duo's outer display, narrow Split View.
    case list
    /// A column per sport across the whole width. The Duo unfolded in either
    /// orientation, iPad, and Mac windows.
    case board

    /// Two 280pt board columns, the 12pt gap between them, and 16pt margins.
    static let boardMinWidth: CGFloat = 604

    /// Width decides only within a regular/regular window. Ordinary iPhones in
    /// landscape reach 724–750pt but stay horizontally compact; Plus/Pro Max
    /// landscape is regular-width but only ~440pt tall. Both keep the phone list.
    init(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?, verticalSizeClass: UserInterfaceSizeClass?) {
        guard horizontalSizeClass == .regular, verticalSizeClass == .regular,
              width >= Self.boardMinWidth else {
            self = .list
            return
        }
        self = .board
    }
}

/// Width at which a detail screen has room for two columns.
enum DetailLayout {
    static let sideBySideMinWidth: CGFloat = 760

    static func isSideBySide(width: CGFloat) -> Bool {
        width >= sideBySideMinWidth
    }
}

// MARK: - Fold state

/// Hinge and fold-line state for foldable iPhones. Everything is `nil`/`.unknown`
/// on devices without a hinge, and before iOS 27.1.
struct FoldState: Equatable {
    enum Hinge: Equatable { case unknown, closed, partiallyOpen, fullyOpen }

    var hinge: Hinge = .unknown
    /// The active fold line, in the reading view's coordinate space.
    var division: CGRect?

    /// Half-open with a fold running across the view: a "stand" posture where
    /// the top half can face the user while the bottom rests on the table.
    var isHalfFoldedAcross: Bool {
        guard hinge == .partiallyOpen, let division else { return false }
        return division.width > division.height
    }
}

#if os(iOS)
/// Reports the device's hinge status and fold line (iOS 27.1+) for the area this
/// view occupies. Put it in a `.background` of the view that should follow the fold.
struct FoldReader: UIViewRepresentable {
    @Binding var state: FoldState

    func makeUIView(context: Context) -> FoldReaderView {
        let view = FoldReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = { newState in
            if state != newState { state = newState }
        }
        return view
    }

    func updateUIView(_ uiView: FoldReaderView, context: Context) {}

    final class FoldReaderView: UIView {
        var onChange: ((FoldState) -> Void)?
        private var hinge: FoldState.Hinge = .unknown
        private var installed = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !installed else { return }
            installed = true
            if #available(iOS 27.1, *) {
                addInteraction(UIHingeInteraction { [weak self] _, update in
                    self?.hinge = Self.hinge(from: update.hinge?.status)
                    self?.publish()
                })
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publish()
        }

        private func publish() {
            var state = FoldState(hinge: hinge)
            if #available(iOS 27.1, *) {
                state.division = reservedRegions(kind: .division).first?.frame
            }
            // Defer: layout passes mustn't write SwiftUI state synchronously.
            DispatchQueue.main.async { [weak self] in self?.onChange?(state) }
        }

        @available(iOS 27.1, *)
        private static func hinge(from status: UIHinge.Status?) -> FoldState.Hinge {
            switch status {
            case .closed: return .closed
            case .partiallyOpen: return .partiallyOpen
            case .fullyOpen: return .fullyOpen
            default: return .unknown
            }
        }
    }
}
#endif

// MARK: - Pinned detail layout

/// A detail screen made of a summary (the scoreboard) and a long body (stats,
/// plays, lineups). It picks the arrangement from the space it gets:
///
/// - **stacked**: one scroll view, capped at a readable width (phones, inspectors).
/// - **side by side**: the summary pinned in its own column, the body scrolling
///   beside it (the Duo unfolded in landscape, iPad).
/// - **half-folded**: the summary above the fold, the body scrolling below it
///   (the Duo stood half-open on a table, iOS 27.1+).
struct PinnedDetailLayout<Summary: View, Details: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var summary: Summary
    @ViewBuilder var details: Details

    @State private var size: CGSize = .zero
    @State private var fold = FoldState()

    private static var summaryColumnWidth: CGFloat { 360 }

    private enum Arrangement: Equatable { case stacked, sideBySide, halfFolded(division: CGRect) }

    private var arrangement: Arrangement {
        if fold.isHalfFoldedAcross, let division = fold.division {
            return .halfFolded(division: division)
        }
        return DetailLayout.isSideBySide(width: size.width) ? .sideBySide : .stacked
    }

    private var isStacked: Bool { arrangement == .stacked }

    var body: some View {
        // `details` keeps one place in the tree (the last scroll view) in every
        // arrangement; only the summary moves. Rebuilding the details would reset
        // their state and restart their loading tasks on every rotation, hinge
        // change, and the first measured frame.
        let layout = if case .halfFolded = arrangement {
            AnyLayout(VStackLayout(spacing: 0))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        }
        layout {
            switch arrangement {
            case .stacked:
                EmptyView()
            case .sideBySide:
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: spacing) { summary }
                            .padding()
                    }
                    .frame(width: Self.summaryColumnWidth)
                    Divider()
                }
            case .halfFolded(let division):
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: spacing) { summary }
                            .padding()
                            .readableWidth()
                    }
                    .frame(height: max(division.minY, 0))
                    // The division's frame includes its margins: keep the body
                    // off the crease.
                    Color.clear.frame(height: division.height)
                }
            }
            ScrollView {
                VStack(spacing: spacing) {
                    if isStacked { summary }
                    details
                }
                .padding()
                .readableWidth()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        #if os(iOS)
        .background(FoldReader(state: $fold))
        #endif
        .animation(.easeInOut(duration: 0.25), value: arrangement)
    }
}
