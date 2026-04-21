//
//  File.swift
//  
//
//  Created by Umar Haroon on 3/9/23.
//

import Foundation

enum NetworkError: Error {
    case invalidLeague
    case invalidData
    case cooledDown(until: Date)
}
