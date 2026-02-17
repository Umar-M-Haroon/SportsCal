//
//  ModelError.swift
//  SportsCal
//
//  Created by Umar Haroon on 5/31/23.
//

import Foundation
import SportsCalModel
public enum ModelErrors: Error {
    case unknownTeam(Game)
}

extension ModelErrors: LocalizedError {
    public var errorDescription: String?{
        switch self {
        case .unknownTeam:
            return NSLocalizedString("Unknown Team", comment: "Unknown Team")
        }
    }
}
