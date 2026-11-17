//
//  MacSnapshotHelpers.swift
//  Tests macOS
//
//  macOS snapshot harness. Hero mode: one PNG per view, light only.
//
//  The test host (Scoreline.app) is App Sandboxed, so the repo checkout is
//  neither readable nor writable from inside a test run. Snapshots therefore
//  flow in two directions:
//   - VERIFY (default): references are read from the test bundle's
//     __Snapshots__ resource folder (committed in the repo, copied into the
//     bundle at build time).
//   - RECORD (RECORD_SNAPSHOTS=1 via TEST_RUNNER_RECORD_SNAPSHOTS=1): new
//     PNGs are written to the sandbox container's tmp/MacSnapshots; copy them
//     back into "Tests macOS/Snapshots/__Snapshots__" and commit.
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
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let record = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

    let hostingView = NSHostingView(rootView:
        view
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
    )
    hostingView.appearance = NSAppearance(named: .aqua)
    hostingView.frame = CGRect(origin: .zero, size: size)

    let directory: String
    if record {
        directory = NSTemporaryDirectory() + "MacSnapshots/MacViewSnapshotTests"
    } else {
        guard let resourceDir = Bundle(for: BundleToken.self)
            .resourceURL?.appendingPathComponent("__Snapshots__/MacViewSnapshotTests").path,
              FileManager.default.fileExists(atPath: resourceDir) else {
            XCTFail(
                "No bundled __Snapshots__ references. Record them with " +
                "TEST_RUNNER_RECORD_SNAPSHOTS=1, copy from the container tmp " +
                "into 'Tests macOS/Snapshots/__Snapshots__', and commit.",
                file: file, line: line
            )
            return
        }
        directory = resourceDir
    }

    let failure = verifySnapshot(
        of: hostingView,
        as: .image(size: size),
        named: "\(name)-mac-light",
        record: record,
        snapshotDirectory: directory,
        fileID: fileID,
        file: file,
        testName: testName,
        line: line,
        column: column
    )
    if record {
        // verifySnapshot returns a "re-recorded" message in record mode; the
        // useful signal is where the PNG landed.
        print("Recorded snapshot into \(directory)")
    } else if let failure {
        XCTFail(failure, file: file, line: line)
    }
}

private final class BundleToken {}
#endif
