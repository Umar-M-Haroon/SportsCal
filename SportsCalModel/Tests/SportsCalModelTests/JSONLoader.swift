//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/8/23.
//

import Foundation

struct JSONLoader {
    static func load(file: String, type: (some Decodable).Type) throws -> some Decodable {
        let decoder = JSONDecoder()
        let thisSourceFile = URL(fileURLWithPath: #file)
        let thisDirectory = thisSourceFile.deletingLastPathComponent()
        let url = thisDirectory.appendingPathComponent("MockJSON/\(file).json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(type.self, from: data)
    }
}
