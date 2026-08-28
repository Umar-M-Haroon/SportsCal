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
    /// Upstream answered with a non-2xx status. Carried explicitly so the failure is
    /// logged as what it is (e.g. "403") instead of surfacing as a downstream decode
    /// error on the error page's `text/html` body.
    case badStatus(code: UInt, url: String)
}
