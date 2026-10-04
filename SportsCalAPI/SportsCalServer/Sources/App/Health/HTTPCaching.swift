//
//  HTTPCaching.swift
//
//  Conditional-GET support (strong ETag + If-None-Match → 304) for the big cached
//  payloads, plus the small helpers that make it cheap: a content version computed
//  once per new source blob, and a stale-on-error Redis cache for upstream calls.
//

import Foundation
import Vapor
import Crypto

// MARK: - Content versions

enum PayloadVersion {
    /// Content hash of `source`: the first 16 bytes of its SHA-256, hex-encoded. Stable
    /// across processes and replicas, so ETags survive restarts and load balancing.
    /// Costs one pass over the bytes; callers memoize it per source generation.
    static func of(_ source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Byte equality without Swift `String ==`, which falls back to Unicode-normalized
    /// comparison for non-ASCII text. Native strings are contiguous UTF-8, so this is a
    /// length check plus one `memcmp`.
    static func bytesEqual(_ a: String, _ b: String) -> Bool {
        guard a.utf8.count == b.utf8.count else { return false }
        var a = a, b = b
        return a.withUTF8 { pa in
            b.withUTF8 { pb in
                pa.count == 0 || memcmp(pa.baseAddress!, pb.baseAddress!, pa.count) == 0
            }
        }
    }
}

/// The content version of a blob read from Redis per request (`/live`, `/teams`),
/// memoized per slot. A hit costs one `memcmp` against the previous source rather than
/// a hash of the whole multi-MB string; only a changed blob is hashed. Lock-based, not an
/// actor, so concurrent requests aren't serialized; two concurrent misses may both hash,
/// which is harmless.
final class SourceVersionMemo: @unchecked Sendable {
    static let shared = SourceVersionMemo()

    private struct Entry {
        let source: String
        let version: String
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func version(slot: String, source: String) -> String {
        if let hit = lock.withLock({ entries[slot] }), PayloadVersion.bytesEqual(hit.source, source) {
            return hit.version
        }
        let version = PayloadVersion.of(source)
        lock.withLock { entries[slot] = Entry(source: source, version: version) }
        return version
    }

    func reset() { lock.withLock { entries = [:] } }
}

// MARK: - Conditional responses

/// Contract (mirrored by the iOS client):
/// - 200 responses carry `ETag: "<32 hex>-<8 hex>"` (strong, quoted) and
///   `Cache-Control: no-cache`. The first part is the source blob's content hash, the
///   second a hash of the response variant (route + every query option that changes the
///   body, e.g. `cfb=1`), so two variants of the same source never share a tag.
/// - A request whose `If-None-Match` lists that tag (or `*`) gets `304 Not Modified`
///   with an empty body and the same `ETag` / `Cache-Control` headers.
/// - Matching uses weak comparison (RFC 9110 §13.1.2): a `W/` prefix is ignored, as is
///   a `-gzip` / `-br` / `-zstd` suffix a compressing proxy may have appended.
enum HTTPCaching {
    static let cacheControl = "no-cache"

    static func etag(version: String, variant: String) -> String {
        "\"\(version)-\(fnv1a32Hex(variant))\""
    }

    /// Whether the request's `If-None-Match` matches `etag`.
    static func notModified(_ req: Request, etag: String) -> Bool {
        let values = req.headers[.ifNoneMatch]
        guard !values.isEmpty else { return false }
        let target = opaque(etag)
        for value in values {
            for candidate in value.split(separator: ",") {
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                if trimmed == "*" { return true }
                if opaque(trimmed) == target { return true }
            }
        }
        return false
    }

    /// A 304 if the client's copy is current, otherwise a 200 with `body()` (only built
    /// when needed) as `text/plain` — the same content type the routes returned as bare
    /// Strings before, so existing clients see no change.
    static func respond(_ req: Request, etag: String, body: () throws -> String) rethrows -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .eTag, value: etag)
        headers.replaceOrAdd(name: .cacheControl, value: cacheControl)
        if notModified(req, etag: etag) {
            return Response(status: .notModified, headers: headers)
        }
        headers.contentType = .plainText
        return Response(status: .ok, headers: headers, body: .init(string: try body()))
    }

    /// The tag with `W/`, quotes and any proxy-added encoding suffix removed.
    static func opaque(_ tag: String) -> String {
        var s = Substring(tag)
        if s.hasPrefix("W/") { s = s.dropFirst(2) }
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 { s = s.dropFirst().dropLast() }
        for suffix in ["-gzip", "-br", "-zstd", "-deflate"] where s.hasSuffix(suffix) {
            s = s.dropLast(suffix.count)
            break
        }
        return String(s)
    }

    /// 32-bit FNV-1a, hex. Stable across processes (unlike `hashValue`).
    static func fnv1a32Hex(_ s: String) -> String {
        var hash: UInt32 = 0x811C9DC5
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return String(format: "%08x", hash)
    }
}

// MARK: - Upstream cache (fresh window + serve stale on failure)

/// Caches an upstream (ESPN) response in the key-value store. Within `freshFor` the
/// cached body is served without calling upstream; after that upstream is retried, and
/// if it fails the last good body is served (for up to `keepFor`) instead of an error.
///
/// One key per entry holding `"<unix seconds>\n<body>"`, so a hit is a single GET.
enum UpstreamCache {
    static func value(
        kv: KeyValueStore,
        key: String,
        freshFor: TimeInterval,
        keepFor: TimeInterval,
        logger: Logger,
        now: Date = Date(),
        fetch: () async throws -> String
    ) async throws -> String {
        let cached = (try? await kv.getString(key)).flatMap(decode)
        if let cached, now.timeIntervalSince(cached.storedAt) < freshFor {
            return cached.body
        }
        do {
            let body = try await fetch()
            try? await kv.setString(key, value: encode(body, storedAt: now), ttl: keepFor)
            return body
        } catch {
            if let cached {
                logger.warning("upstream fetch failed, serving stale cache", metadata: [
                    "key": "\(key)",
                    "ageSeconds": "\(Int(now.timeIntervalSince(cached.storedAt)))",
                    "error": "\(error)",
                ])
                return cached.body
            }
            throw error
        }
    }

    static func encode(_ body: String, storedAt: Date) -> String {
        "\(Int(storedAt.timeIntervalSince1970))\n\(body)"
    }

    static func decode(_ raw: String) -> (storedAt: Date, body: String)? {
        guard let newline = raw.firstIndex(of: "\n"),
              let seconds = TimeInterval(raw[raw.startIndex..<newline]) else { return nil }
        return (Date(timeIntervalSince1970: seconds), String(raw[raw.index(after: newline)...]))
    }
}
