import Foundation

/// Minimal CBOR (RFC 8949) decoder covering exactly the subset App Attest uses:
/// unsigned/negative ints, byte strings, text strings, arrays, maps, and the
/// simple values true/false/null.
///
/// Why hand-rolled rather than a package: this parser sits on the untrusted edge
/// of the attestation path — every byte it reads came from a caller we haven't
/// authenticated yet. A ~150-line decoder we can read end to end is a smaller
/// risk than a transitive dependency, and the App Attest grammar is tiny.
///
/// Deliberately strict: indefinite-length items, tags, and floats are rejected
/// rather than skipped, and trailing bytes after the top-level item are an error.
/// Anything Apple doesn't emit is malformed input by definition.
enum CBOR: Equatable {
    case unsignedInt(UInt64)
    case negativeInt(Int64)
    case byteString([UInt8])
    case textString(String)
    case array([CBOR])
    case map([CBORMapKey: CBOR])
    case boolean(Bool)
    case null

    // MARK: Convenience accessors

    var bytes: [UInt8]? { if case .byteString(let b) = self { return b }; return nil }
    var text: String?   { if case .textString(let s) = self { return s }; return nil }
    var arrayValue: [CBOR]? { if case .array(let a) = self { return a }; return nil }
    var intValue: Int? {
        switch self {
        case .unsignedInt(let v): return Int(exactly: v)
        case .negativeInt(let v): return Int(exactly: v)
        default: return nil
        }
    }

    /// Subscript by text key — the only map shape App Attest blobs use at the
    /// top level (`fmt` / `attStmt` / `authData`).
    subscript(key: String) -> CBOR? {
        guard case .map(let m) = self else { return nil }
        return m[.text(key)]
    }

    /// Subscript by integer key — COSE keys are negative/positive ints.
    subscript(key: Int) -> CBOR? {
        guard case .map(let m) = self else { return nil }
        return m[.int(key)]
    }
}

/// CBOR map keys are arbitrary CBOR values; App Attest only ever uses text
/// (attestation object) and integers (COSE public key), so we model just those.
enum CBORMapKey: Hashable {
    case text(String)
    case int(Int)
}

enum CBORError: Error, CustomStringConvertible, Equatable {
    case truncated
    case unsupportedMajorType(UInt8)
    case indefiniteLength
    case invalidUTF8
    case duplicateMapKey
    case unsupportedMapKey
    case trailingBytes
    case depthLimitExceeded
    case lengthTooLarge

    var description: String {
        switch self {
        case .truncated:                 return "CBOR input ended mid-item"
        case .unsupportedMajorType(let t): return "unsupported CBOR major type \(t)"
        case .indefiniteLength:          return "indefinite-length CBOR items are not accepted"
        case .invalidUTF8:               return "CBOR text string was not valid UTF-8"
        case .duplicateMapKey:           return "duplicate CBOR map key"
        case .unsupportedMapKey:         return "CBOR map key was neither text nor integer"
        case .trailingBytes:             return "trailing bytes after top-level CBOR item"
        case .depthLimitExceeded:        return "CBOR nesting too deep"
        case .lengthTooLarge:            return "CBOR item length exceeds input size"
        }
    }
}

struct CBORDecoder {
    private let bytes: [UInt8]
    private var index: Int = 0
    private var depth: Int = 0

    /// Bounded to keep a hostile blob from recursing us to death. App Attest
    /// objects nest 3 deep; 16 is slack with no legitimate use above it.
    private static let maxDepth = 16

    private init(_ bytes: [UInt8]) { self.bytes = bytes }

    /// Decodes exactly one top-level item and requires the input to end there.
    static func decode(_ data: Data) throws -> CBOR {
        var decoder = CBORDecoder([UInt8](data))
        let value = try decoder.decodeItem()
        guard decoder.index == decoder.bytes.count else { throw CBORError.trailingBytes }
        return value
    }

    // MARK: - Reader primitives

    private mutating func readByte() throws -> UInt8 {
        guard index < bytes.count else { throw CBORError.truncated }
        defer { index += 1 }
        return bytes[index]
    }

    private mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, index + count <= bytes.count else { throw CBORError.truncated }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    /// Reads the argument encoded in the additional-information bits, following
    /// the 1/2/4/8-byte extensions. 31 (indefinite length) is rejected outright.
    private mutating func readArgument(_ additional: UInt8) throws -> UInt64 {
        switch additional {
        case 0...23: return UInt64(additional)
        case 24: return UInt64(try readByte())
        case 25:
            let b = try readBytes(2)
            return (UInt64(b[0]) << 8) | UInt64(b[1])
        case 26:
            let b = try readBytes(4)
            return b.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        case 27:
            let b = try readBytes(8)
            return b.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        case 31: throw CBORError.indefiniteLength
        default: throw CBORError.truncated
        }
    }

    /// Converts a CBOR length argument to an Int, rejecting anything that
    /// couldn't possibly fit in the remaining input before we try to allocate.
    private func checkedLength(_ argument: UInt64) throws -> Int {
        guard let length = Int(exactly: argument),
              length <= bytes.count - index else { throw CBORError.lengthTooLarge }
        return length
    }

    // MARK: - Item decoding

    private mutating func decodeItem() throws -> CBOR {
        guard depth < Self.maxDepth else { throw CBORError.depthLimitExceeded }

        let initial = try readByte()
        let major = initial >> 5
        let additional = initial & 0x1f

        switch major {
        case 0:
            return .unsignedInt(try readArgument(additional))
        case 1:
            // Major type 1 encodes -1 - n.
            let n = try readArgument(additional)
            guard let signed = Int64(exactly: n) else { throw CBORError.lengthTooLarge }
            return .negativeInt(-1 - signed)
        case 2:
            return .byteString(try readBytes(try checkedLength(try readArgument(additional))))
        case 3:
            let raw = try readBytes(try checkedLength(try readArgument(additional)))
            guard let s = String(bytes: raw, encoding: .utf8) else { throw CBORError.invalidUTF8 }
            return .textString(s)
        case 4:
            let count = try checkedLength(try readArgument(additional))
            depth += 1; defer { depth -= 1 }
            var items: [CBOR] = []
            items.reserveCapacity(count)
            for _ in 0..<count { items.append(try decodeItem()) }
            return .array(items)
        case 5:
            let count = try checkedLength(try readArgument(additional))
            depth += 1; defer { depth -= 1 }
            var map: [CBORMapKey: CBOR] = [:]
            for _ in 0..<count {
                let key = try decodeMapKey()
                guard map[key] == nil else { throw CBORError.duplicateMapKey }
                map[key] = try decodeItem()
            }
            return .map(map)
        case 7:
            switch additional {
            case 20: return .boolean(false)
            case 21: return .boolean(true)
            case 22, 23: return .null   // null / undefined
            default: throw CBORError.unsupportedMajorType(major)
            }
        default:
            // Major type 6 is tags — App Attest never emits them.
            throw CBORError.unsupportedMajorType(major)
        }
    }

    /// Map keys must be text or integer. Anything else is malformed for our
    /// grammar, and silently accepting it would let a caller smuggle in a
    /// shape our lookups can't see.
    private mutating func decodeMapKey() throws -> CBORMapKey {
        switch try decodeItem() {
        case .textString(let s): return .text(s)
        case .unsignedInt(let v):
            guard let i = Int(exactly: v) else { throw CBORError.unsupportedMapKey }
            return .int(i)
        case .negativeInt(let v):
            guard let i = Int(exactly: v) else { throw CBORError.unsupportedMapKey }
            return .int(i)
        default: throw CBORError.unsupportedMapKey
        }
    }
}

/// Decodes one CBOR item from the *front* of `data` and reports how many bytes
/// it consumed. App Attest's `authenticatorData` ends with a COSE key that runs
/// to the end of the buffer, so this is only needed when a caller must know
/// where a nested item stopped.
extension CBORDecoder {
    static func decodePrefix(_ data: Data) throws -> (value: CBOR, consumed: Int) {
        var decoder = CBORDecoder([UInt8](data))
        let value = try decoder.decodeItem()
        return (value, decoder.index)
    }
}
