//
//  LossyDecoding.swift
//  SportsCalModel
//
//  Lenient decoding for the schedule payload. One malformed game, or one broken
//  enrichment blob, used to fail the whole `LiveScore` (and every sport with it). Now
//  a bad game is skipped, a bad optional blob reads as nil, a bad sport bucket drops
//  only that sport — and each recovery is recorded as a `DecodeIssue` so the app can
//  report it instead of the failure going silent.
//
//  Everything here runs inside the caller's decoder: no JSONSerialization round-trips,
//  and nothing extra happens on the happy path beyond what the synthesized decoders did.
//

import Foundation

// MARK: - Issues

/// One thing a lenient decode recovered from.
public struct DecodeIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Equatable, Hashable, Sendable {
        /// An element of an array (a game) failed and was skipped.
        case skippedElement
        /// An optional field or enrichment blob failed and was read as nil.
        case droppedField
    }

    public let kind: Kind
    /// Coding path of the recovered value, e.g. `nfl.events[12]` or `f1Standings`.
    public let path: String
    /// The underlying decoding error, condensed.
    public let reason: String
    /// The skipped game's `idEvent`, when it could still be read.
    public let idEvent: String?

    public init(kind: Kind, path: String, reason: String, idEvent: String? = nil) {
        self.kind = kind
        self.path = path
        self.reason = reason
        self.idEvent = idEvent
    }

    public var description: String {
        let id = idEvent.map { " (idEvent \($0))" } ?? ""
        switch kind {
        case .skippedElement: return "skipped \(path)\(id): \(reason)"
        case .droppedField: return "dropped \(path)\(id): \(reason)"
        }
    }
}

// MARK: - Reporting

/// Where lenient-decode recoveries go.
///
/// - A top-level `LiveScore` decode batches everything it recovered from into **one**
///   call to `issueHandler` (a summary string), so a bad schedule produces one report,
///   not one per game.
/// - A `LiveEvent` or `Game` decoded on its own reports each issue as it happens.
/// - Inside `collecting(_:)`, issues are returned to the caller instead and the
///   handler is not called.
///
/// Thread-safe: the handler is lock-protected, and in-flight collection is per thread
/// (a decode runs synchronously on one thread).
public enum ModelDecodeDiagnostics {
    private static let lock = NSLock()
    private static var _issueHandler: ((String) -> Void)?

    /// Called with a human-readable summary whenever lenient decoding recovers from bad
    /// data outside a `collecting(_:)` scope. Wire it to crash/analytics reporting.
    /// Called on the decoding thread.
    public static var issueHandler: ((String) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _issueHandler }
        set { lock.lock(); _issueHandler = newValue; lock.unlock() }
    }

    /// Runs `body` (typically a `JSONDecoder.decode` call) and returns its value with
    /// every issue lenient decoding recovered from along the way. The handler is not
    /// called for these.
    public static func collecting<T>(_ body: () throws -> T) rethrows -> (value: T, issues: [DecodeIssue]) {
        let scope = Scope()
        let previous = Scope.current
        Scope.current = scope
        defer { Scope.current = previous }
        let value = try body()
        return (value, scope.issues)
    }

    // MARK: Internal

    static func record(_ issue: DecodeIssue) {
        if let scope = Scope.current {
            scope.issues.append(issue)
        } else {
            issueHandler?("SportsCalModel decode: \(issue)")
        }
    }

    /// Collects the issues of one `LiveScore` decode and hands them on as one report:
    /// to an enclosing scope if there is one, else to the handler as a summary.
    static func batching<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let previous = Scope.current
        // Inside an explicit `collecting` scope, just let issues flow into it.
        if previous != nil { return try body() }
        let scope = Scope()
        Scope.current = scope
        defer {
            Scope.current = previous
            if !scope.issues.isEmpty { issueHandler?(summary(label, scope.issues)) }
        }
        return try body()
    }

    static func summary(_ label: String, _ issues: [DecodeIssue]) -> String {
        let skipped = issues.filter { $0.kind == .skippedElement }
        let dropped = issues.count - skipped.count
        var parts: [String] = []
        if !skipped.isEmpty {
            // Group skipped elements by their bucket ("nfl.events[3]" → "nfl").
            var perBucket: [String: Int] = [:]
            for issue in skipped {
                let bucket = issue.path.split(separator: ".").first.map(String.init) ?? issue.path
                perBucket[bucket, default: 0] += 1
            }
            let detail = perBucket.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
            parts.append("skipped \(skipped.count) element(s) [\(detail)]")
        }
        if dropped > 0 { parts.append("dropped \(dropped) field(s)") }
        let examples = issues.prefix(3).map(\.description).joined(separator: "; ")
        return "SportsCalModel decode: \(label) recovered from \(issues.count) issue(s): \(parts.joined(separator: ", ")). First: \(examples)"
    }

    final class Scope {
        var issues: [DecodeIssue] = []

        private static let key = "SportsCalModel.DecodeIssueScope"

        static var current: Scope? {
            get { Thread.current.threadDictionary[key] as? Scope }
            set { Thread.current.threadDictionary[key] = newValue }
        }
    }

    /// `nfl.events[3].intHomeScore`
    static func pathString(_ path: [CodingKey]) -> String {
        var out = ""
        for key in path {
            if let index = key.intValue {
                out += "[\(index)]"
            } else {
                if !out.isEmpty { out += "." }
                out += key.stringValue
            }
        }
        return out
    }

    /// One line per error: what went wrong and where inside the value.
    static func reason(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        switch error {
        case .typeMismatch(let type, let context):
            return "type mismatch (\(type)) at \(pathString(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "missing value (\(type)) at \(pathString(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(pathString(context.codingPath))"
        case .dataCorrupted(let context):
            return "corrupted data at \(pathString(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}

public extension LiveScore {
    /// Convenience for `ModelDecodeDiagnostics.issueHandler`: receives one summary per
    /// `LiveScore` decode that skipped games or dropped broken fields.
    static var decodeIssueHandler: ((String) -> Void)? {
        get { ModelDecodeDiagnostics.issueHandler }
        set { ModelDecodeDiagnostics.issueHandler = newValue }
    }
}

// MARK: - Helpers

/// Decodes any JSON value and discards it, so an unkeyed container can step past an
/// element that failed to decode. Reads the element's `idEvent` on the way when it
/// is an object, for the diagnostic. Never throws.
private struct SkippedElement: Decodable {
    let idEvent: String?

    private enum CodingKeys: String, CodingKey { case idEvent }

    init(from decoder: Decoder) {
        idEvent = (try? decoder.container(keyedBy: CodingKeys.self))
            .flatMap { try? $0.decodeIfPresent(String.self, forKey: .idEvent) }
    }
}

extension UnkeyedDecodingContainer {
    /// Decodes the remaining elements, skipping (and recording) any that fail.
    mutating func decodeLossyElements<T: Decodable>(_ type: T.Type) throws -> [T] {
        var out: [T] = []
        if let count { out.reserveCapacity(count) }
        while !isAtEnd {
            let index = currentIndex
            do {
                out.append(try decode(T.self))
            } catch {
                // A failed decode leaves the index where it was; step past the element
                // (`decodeNil` consumes a null, `SkippedElement` anything else).
                var idEvent: String?
                if (try? decodeNil()) != true {
                    idEvent = try decode(SkippedElement.self).idEvent
                }
                ModelDecodeDiagnostics.record(DecodeIssue(
                    kind: .skippedElement,
                    path: ModelDecodeDiagnostics.pathString(codingPath) + "[\(index)]",
                    reason: ModelDecodeDiagnostics.reason(error),
                    idEvent: idEvent
                ))
                // Belt and braces: never spin on an element we couldn't step past.
                if currentIndex == index { break }
            }
        }
        return out
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent`, except a value that is present but malformed reads as nil
    /// (and is recorded) instead of failing the enclosing value.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(T.self, forKey: key)
        } catch {
            ModelDecodeDiagnostics.record(DecodeIssue(
                kind: .droppedField,
                path: ModelDecodeDiagnostics.pathString(codingPath + [key]),
                reason: ModelDecodeDiagnostics.reason(error)
            ))
            return nil
        }
    }

    /// Decodes an array under `key` element by element, skipping malformed elements.
    /// Nil when the key is absent or null; throws only if the value isn't an array.
    func decodeLossyArrayIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        var nested = try nestedUnkeyedContainer(forKey: key)
        return try nested.decodeLossyElements(T.self)
    }
}
