//
//  Indirect.swift
//  SportsCalModel
//
//  Stores a large, usually-nil value out of line, behind one pointer.
//

import Foundation

/// Keeps an optional value in a shared, immutable heap box so the enclosing
/// struct only carries a pointer.
///
/// `Game` is copied into every derived collection the app keeps (the
/// schedule, per-sport buckets, filtered/sorted/day caches…). Its rarely-set
/// payloads (`situation`, `scoreboardExtras`, …) were stored inline and made
/// the struct ~1.9 KB, so each copy of a ~4,000-game schedule cost ~8 MB.
/// Boxed, an unset field costs 8 bytes and a set one is shared by every copy.
///
/// The box is immutable: writing replaces it, so value semantics hold.
@propertyWrapper
public struct Indirect<Value> {
    private final class Box: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private var box: Box?

    public init() {
        box = nil
    }

    public init(wrappedValue: Value?) {
        box = wrappedValue.map(Box.init)
    }

    public var wrappedValue: Value? {
        get { box?.value }
        set { box = newValue.map(Box.init) }
    }
}

extension Indirect: Equatable where Value: Equatable {
    public static func == (lhs: Indirect, rhs: Indirect) -> Bool {
        if lhs.box === rhs.box { return true }
        return lhs.wrappedValue == rhs.wrappedValue
    }
}

extension Indirect: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension Indirect: Sendable where Value: Sendable {}
