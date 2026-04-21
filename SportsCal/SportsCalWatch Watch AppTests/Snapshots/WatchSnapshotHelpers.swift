//
//  WatchSnapshotHelpers.swift
//  SportsCalWatch Watch AppTests
//
//  Watch snapshot harness. Uses a fixed watch-sized frame since
//  ViewImageConfig has limited watchOS presets across library versions.
//

#if canImport(SnapshotTesting) && os(watchOS)
import SnapshotTesting
import SwiftUI
import WatchKit
import XCTest

/// Apple Watch Series 9 45mm screen size (approximately). Adjust per design needs.
private let defaultWatchSize = CGSize(width: 198, height: 242)

@MainActor
func assertWatchReviewSnapshots<V: View>(
    of view: V,
    named name: String,
    size: CGSize = defaultWatchSize,
    record: Bool = false,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let exportDir = watchReviewExportDirectory(file: file)
    let framed = view.frame(width: size.width, height: size.height)
    assertSnapshot(
        of: framed,
        as: .image(layout: .fixed(width: size.width, height: size.height)),
        named: "\(name)-watch",
        record: record,
        snapshotDirectory: exportDir,
        file: file,
        testName: "",
        line: line
    )
}

private func watchReviewExportDirectory(file: StaticString) -> String {
    // Walk: Snapshots/File.swift -> Snapshots/ -> SportsCalWatch Watch AppTests/ -> SportsCal/
    let filePath = "\(file)"
    let url = URL(fileURLWithPath: filePath)
    let sportsCalDir = url
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return sportsCalDir
        .appendingPathComponent("SportsCalTests")
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent("ReviewExport")
        .path
}
#endif
