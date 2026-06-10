//
//  SnapshotHelpers.swift
//  SportsCalTests
//
//  Render harness for SwiftUI snapshot tests. Hero mode: single device,
//  light only, one PNG per view. PNGs land next to the test file under
//  `__Snapshots__/<TestClass>/` (library default).
//

#if canImport(SnapshotTesting)
import SnapshotTesting
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import XCTest

struct SnapshotDevice {
    let slug: String
    let config: ViewImageConfig

    static let iPhone = SnapshotDevice(slug: "iphone", config: .iPhone13Pro)
    static let iPad = SnapshotDevice(slug: "ipad", config: .iPadPro11)
}

struct SnapshotScheme {
    let slug: String
    let userInterfaceStyle: UIUserInterfaceStyle

    static let light = SnapshotScheme(slug: "light", userInterfaceStyle: .light)
    static let dark = SnapshotScheme(slug: "dark", userInterfaceStyle: .dark)
}

/// Renders one PNG per (device × scheme). Default: iPhone × light (hero mode).
@MainActor
func assertReviewSnapshots<V: View>(
    of view: V,
    named name: String,
    devices: [SnapshotDevice] = [.iPhone],
    schemes: [SnapshotScheme] = [.light],
    record: Bool = false,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    for device in devices {
        for scheme in schemes {
            let traits = UITraitCollection(userInterfaceStyle: scheme.userInterfaceStyle)
            let wrapped = view
                .environment(\.colorScheme, scheme.userInterfaceStyle == .dark ? .dark : .light)
            assertSnapshot(
                of: wrapped,
                as: .wait(for: 6.0, on: .image(layout: .device(config: device.config), traits: traits)),
                named: "\(name)-\(device.slug)-\(scheme.slug)",
                record: record,
                fileID: fileID,
                file: file,
                testName: testName,
                line: line,
                column: column
            )
        }
    }
}
#endif
