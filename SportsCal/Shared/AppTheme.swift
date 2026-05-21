//
//  AppTheme.swift
//  SportsCal
//

import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case classic
    case ambient
    case efRemix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .ambient: return "Ambient"
        case .efRemix: return "Modern"
        }
    }
}
