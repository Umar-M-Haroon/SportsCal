//
//  APIVersionMiddleware.swift
//
//
//  Created by Claude on 2025.
//

import Vapor

/// Middleware that adds API versioning headers to all responses.
/// - X-API-Version: Current API version (e.g., "2025")
/// - X-Min-App-Version: Minimum iOS app version required (e.g., "1.5.0")
struct APIVersionMiddleware: AsyncMiddleware {
    /// Current API version - update when making breaking changes
    static let currentVersion = "2025"

    /// Minimum app version required to use this API
    /// Increment when deploying breaking changes
    static let minAppVersion = "1.5.0"

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        var response = try await next.respond(to: request)
        response.headers.add(name: "X-API-Version", value: Self.currentVersion)
        response.headers.add(name: "X-Min-App-Version", value: Self.minAppVersion)
        return response
    }
}
