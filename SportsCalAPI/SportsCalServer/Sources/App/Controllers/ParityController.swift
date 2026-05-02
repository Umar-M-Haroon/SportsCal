//
//  ParityController.swift
//  SportsCalServer
//
//  Server-side proxy for comparing responses between the current (local) server
//  and a target environment (dev or prod). Keeps browser-side CORS out of the
//  picture: the admin dashboard calls /api/admin/parity?target=prod and this
//  controller fetches both sides on the dashboard's behalf, strips noisy
//  timestamp fields, and returns a per-endpoint diff summary.
//

import Vapor

struct ParityController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let parity = routes.grouped("api", "admin", "parity")
        parity.get(use: runParity)
    }

    // MARK: - Configuration

    /// Endpoints that are compared. Keep each response small; the goal is
    /// schema and content parity, not load testing.
    private static let endpoints: [String] = [
        "/v2025/schedules",
        "/v2025/live",
        "/v2025/teams",
        "/v2025/sport/basketball",
        "/v2025/sport/soccer",
        "/v2025/sport/racing",
        "/v2025/standings/4387",
        "/v2025/widget/schedule?sports=basketball,soccer,mlb&limit=6",
        "/v2025/all-live-games"
    ]

    /// Top-level keys stripped before comparison because they change every
    /// request. Anything deeper than top-level slips through — we also walk
    /// the tree below to catch nested instances.
    private static let noisyKeys: Set<String> = [
        "strTimestamp", "updated", "isoDate", "fetchedAt", "timestamp", "lastPlayId"
    ]

    // MARK: - Routes

    struct ParityResult: Content {
        let endpoint: String
        let localStatus: Int
        let targetStatus: Int
        let match: Bool
        let diff: String?
        let localBytes: Int
        let targetBytes: Int
    }

    struct ParityResponse: Content {
        let target: String
        let localBase: String
        let targetBase: String
        let results: [ParityResult]
        let matches: Int
        let mismatches: Int
        let errors: Int
    }

    func runParity(req: Request) async throws -> ParityResponse {
        let targetParam = (try? req.query.get(String.self, at: "target")) ?? "prod"
        let targetBase = self.targetBaseURL(for: targetParam)
        let localBase = self.localBaseURL(for: req)
        let apiKey = Environment.get("X_API_KEY") ?? Environment.get("SPORTSCAL_API_KEY") ?? ""

        var results: [ParityResult] = []
        var matches = 0
        var mismatches = 0
        var errors = 0

        for endpoint in Self.endpoints {
            let result = await compareOne(
                endpoint: endpoint,
                localBase: localBase,
                targetBase: targetBase,
                apiKey: apiKey,
                client: req.client
            )
            switch (result.localStatus, result.targetStatus, result.match) {
            case (200, 200, true):  matches += 1
            case (200, 200, false): mismatches += 1
            default:                errors += 1
            }
            results.append(result)
        }

        return ParityResponse(
            target: targetParam,
            localBase: localBase,
            targetBase: targetBase,
            results: results,
            matches: matches,
            mismatches: mismatches,
            errors: errors
        )
    }

    // MARK: - Helpers

    private func targetBaseURL(for target: String) -> String {
        switch target.lowercased() {
        case "prod", "production":
            return Environment.get("PARITY_PROD_URL") ?? "https://api.sportscal.app"
        case "dev", "development", "tailscale":
            return Environment.get("PARITY_DEV_URL") ?? "http://100.68.255.93:8080"
        default:
            return target.hasPrefix("http") ? target : "https://\(target)"
        }
    }

    private func localBaseURL(for req: Request) -> String {
        // Prefer calling ourselves via the container-internal port to avoid a
        // round-trip through the reverse proxy.
        Environment.get("PARITY_LOCAL_URL") ?? "http://127.0.0.1:8080"
    }

    private func compareOne(
        endpoint: String,
        localBase: String,
        targetBase: String,
        apiKey: String,
        client: Client
    ) async -> ParityResult {
        async let localFetch = fetch(base: localBase, endpoint: endpoint, apiKey: apiKey, client: client)
        async let targetFetch = fetch(base: targetBase, endpoint: endpoint, apiKey: apiKey, client: client)
        let (local, target) = await (localFetch, targetFetch)

        guard local.status == 200, target.status == 200,
              let localJSON = local.json, let targetJSON = target.json else {
            return ParityResult(
                endpoint: endpoint,
                localStatus: local.status,
                targetStatus: target.status,
                match: false,
                diff: "non-200 or unparseable response",
                localBytes: local.bytes,
                targetBytes: target.bytes
            )
        }

        let normalizedLocal = normalize(localJSON)
        let normalizedTarget = normalize(targetJSON)
        let match = jsonEqual(normalizedLocal, normalizedTarget)
        let diff: String? = match ? nil : describeDiff(local: normalizedLocal, target: normalizedTarget)

        return ParityResult(
            endpoint: endpoint,
            localStatus: local.status,
            targetStatus: target.status,
            match: match,
            diff: diff,
            localBytes: local.bytes,
            targetBytes: target.bytes
        )
    }

    private struct FetchResult {
        let status: Int
        let bytes: Int
        let json: Any?
    }

    private func fetch(base: String, endpoint: String, apiKey: String, client: Client) async -> FetchResult {
        let urlString = base + endpoint
        let uri = URI(string: urlString)
        do {
            var headers = HTTPHeaders()
            if !apiKey.isEmpty { headers.add(name: "X-API-Key", value: apiKey) }
            let response = try await client.get(uri, headers: headers)
            let status = Int(response.status.code)
            let bodyBytes = response.body?.readableBytes ?? 0
            guard let body = response.body else {
                return FetchResult(status: status, bytes: 0, json: nil)
            }
            var buf = body
            let data = buf.readData(length: buf.readableBytes) ?? Data()
            let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return FetchResult(status: status, bytes: bodyBytes, json: json)
        } catch {
            return FetchResult(status: 0, bytes: 0, json: nil)
        }
    }

    /// Recursively strips known-noisy keys from dictionaries/arrays so the diff
    /// only surfaces structural or semantic differences.
    private func normalize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if Self.noisyKeys.contains(k) { continue }
                out[k] = normalize(v)
            }
            return out
        }
        if let arr = value as? [Any] {
            return arr.map { normalize($0) }
        }
        return value
    }

    private func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        guard let aData = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys, .fragmentsAllowed]),
              let bData = try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys, .fragmentsAllowed]) else {
            return false
        }
        return aData == bData
    }

    /// Returns a short human-readable summary of where the two sides disagree.
    /// Not a full diff — just enough to point a developer at the likely cause.
    private func describeDiff(local: Any, target: Any) -> String {
        // Count top-level keys / array sizes as a first-pass summary.
        if let localDict = local as? [String: Any], let targetDict = target as? [String: Any] {
            let onlyLocal = Set(localDict.keys).subtracting(targetDict.keys)
            let onlyTarget = Set(targetDict.keys).subtracting(localDict.keys)
            var parts: [String] = []
            if !onlyLocal.isEmpty { parts.append("only-local: \(onlyLocal.sorted().joined(separator: ","))") }
            if !onlyTarget.isEmpty { parts.append("only-target: \(onlyTarget.sorted().joined(separator: ","))") }
            for key in localDict.keys where targetDict[key] != nil {
                if let la = localDict[key] as? [Any], let ta = targetDict[key] as? [Any], la.count != ta.count {
                    parts.append("\(key) count: local=\(la.count) target=\(ta.count)")
                }
            }
            if parts.isEmpty { parts.append("structural match, value differences below top level") }
            return parts.joined(separator: "; ")
        }
        if let localArr = local as? [Any], let targetArr = target as? [Any] {
            return "array sizes: local=\(localArr.count) target=\(targetArr.count)"
        }
        return "scalar mismatch"
    }
}
