//
//  CGFloat+Space.swift
//  SportsCal — Design System v1.0
//
//  8-pt grid with a 4-pt micro step. Names map to use, not value, so the
//  underlying number can be tuned without renaming call sites. Hit-target
//  minimums per Apple HIG.
//

import CoreGraphics

public extension CGFloat {
    // MARK: - Spacing scale

    /// 4 pt — hairline gaps, tight inline groupings.
    static let appSpace1: CGFloat = 4
    /// 8 pt — inline tags, sub-text spacing.
    static let appSpace2: CGFloat = 8
    /// 12 pt — row internal padding.
    static let appSpace3: CGFloat = 12
    /// 16 pt — screen edge insets, card padding.
    static let appSpace4: CGFloat = 16
    /// 24 pt — between sections.
    static let appSpace5: CGFloat = 24
    /// 32 pt — screen-level breathing room.
    static let appSpace6: CGFloat = 32
    /// 48 pt — empty-state hero padding.
    static let appSpace7: CGFloat = 48

    // MARK: - Hit targets

    /// 44 pt — iOS minimum interactive size per HIG.
    static let appHit: CGFloat = 44
    /// 32 pt — watchOS minimum.
    static let appHitWatch: CGFloat = 32
    /// 28 pt — macOS minimum.
    static let appHitMac: CGFloat = 28
}
