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
}

// MARK: - Embedded detail

extension EnvironmentValues {
    /// True when a detail screen is shown beside a list (the split layout's
    /// detail column) rather than pushed. It then leaves the window's title alone.
    @Entry var isEmbeddedDetail = false
}

private struct DetailNavigationTitle: ViewModifier {
    let title: String
    @Environment(\.isEmbeddedDetail) private var isEmbeddedDetail

    func body(content: Content) -> some View {
        if isEmbeddedDetail {
            content
        } else {
            content.navigationTitle(title)
        }
    }
}

extension View {
    /// A detail screen's title, skipped when the screen is embedded beside a list,
    /// where it would replace the window's own title.
    func detailNavigationTitle(_ title: String) -> some View {
        modifier(DetailNavigationTitle(title: title))
    }
}

// MARK: - Games layout

/// How the Games tab lays out for a given width (iOS).
enum GamesLayout: Equatable {
    /// One scrolling list. iPhone, the Duo's outer display, narrow Split View.
    case list
    /// List with the selected game's detail beside it. The Duo unfolded in
    /// landscape, iPad portrait, mid-size windows. Below 720pt two columns are too
    /// cramped (and iOS floats the detail column over the list instead of beside
    /// it), so the Duo unfolded in portrait (669pt) keeps the single list.
    case split
    /// A column per sport. Wide iPad and Mac windows.
    case board

    static let splitMinWidth: CGFloat = 720
    static let boardMinWidth: CGFloat = 1100

    init(width: CGFloat) {
        switch width {
        case ..<Self.splitMinWidth: self = .list
        case ..<Self.boardMinWidth: self = .split
        default: self = .board
        }
    }
}

/// Width at which a detail screen has room for two columns.
enum DetailLayout {
    static let sideBySideMinWidth: CGFloat = 760
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
    @ViewBuilder var summary: Summary
    @ViewBuilder var details: Details

    @State private var size: CGSize = .zero
    @State private var fold = FoldState()

    private static var summaryColumnWidth: CGFloat { 360 }

    private enum Arrangement: Equatable { case stacked, sideBySide, halfFolded(foldY: CGFloat) }

    private var arrangement: Arrangement {
        if fold.isHalfFoldedAcross, let division = fold.division {
            return .halfFolded(foldY: division.minY)
        }
        return size.width >= DetailLayout.sideBySideMinWidth ? .sideBySide : .stacked
    }

    var body: some View {
        Group {
            switch arrangement {
            case .stacked:
                ScrollView {
                    VStack(spacing: 24) {
                        summary
                        details
                    }
                    .padding()
                    .readableWidth()
                }
            case .sideBySide:
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) { summary }
                            .padding()
                    }
                    .frame(width: Self.summaryColumnWidth)
                    Divider()
                    ScrollView {
                        VStack(spacing: 24) { details }
                            .padding()
                            .readableWidth()
                    }
                }
            case .halfFolded(let foldY):
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) { summary }
                            .padding()
                            .readableWidth()
                    }
                    .frame(height: max(foldY, 0))
                    ScrollView {
                        VStack(spacing: 24) { details }
                            .padding()
                            .readableWidth()
                    }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        #if os(iOS)
        .background(FoldReader(state: $fold))
        #endif
        .animation(.easeInOut(duration: 0.25), value: arrangement)
    }
}
