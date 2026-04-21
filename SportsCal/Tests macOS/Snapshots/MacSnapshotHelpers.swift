//
//  MacSnapshotHelpers.swift
//  Tests macOS
//
//  macOS snapshot harness. Hero mode: one PNG per view, light only.
//

#if canImport(SnapshotTesting) && os(macOS)
import SnapshotTesting
import SwiftUI
import AppKit
import XCTest

@MainActor
func assertMacReviewSnapshots<V: View>(
    of view: V,
    named name: String,
    size: CGSize = CGSize(width: 900, height: 700),
    record: Bool = true,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let hostingView = NSHostingView(rootView:
        view
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
    )
    hostingView.appearance = NSAppearance(named: .aqua)
    hostingView.frame = CGRect(origin: .zero, size: size)
    assertSnapshot(
        of: hostingView,
        as: .image(size: size),
        named: "\(name)-mac-light",
        record: record,
        fileID: fileID,
        file: file,
        testName: testName,
        line: line,
        column: column
    )
}
#endif
