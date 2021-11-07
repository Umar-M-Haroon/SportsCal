//
//  NetworkErrors.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/2/21.
//

import Foundation
public enum NetworkErrors: Error {
    case invalidKey
}

extension NetworkErrors: LocalizedError {
    public var errorDescription: String?{
        switch self {
        case .invalidKey:
            return NSLocalizedString("LOCALIZED_INVALID_API_KEY", comment: "Invalid API Key")
        }
    }
}
