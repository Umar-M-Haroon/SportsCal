//
//  NetworkHandler.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/2/21.
//

import Foundation
import Combine
struct NetworkHandler {
    
    @available(iOS 15.0, *)
    func handleCall(type: SportTypes? = nil, year: String) async throws -> Sports {
        var urlString = "https://sportscal.komodollc.com"
        if let type = type {
            urlString = "https://sportscal.komodollc.com/\(type.rawValue)"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(Sports.self, from: data)
    }
    func handleCall(type: SportTypes? = nil) -> AnyPublisher<Sports, Error> {
        var urlString = "https://sportscal.komodollc.com"
        if let type = type {
            urlString = "https://sportscal.komodollc.com/\(type.rawValue)"
        }
        let url = URL(string: urlString)!
        return URLSession.shared.dataTaskPublisher(for: url)
            .map({ response in
                return response.data
            })
            .decode(type: Sports.self, decoder: JSONDecoder())
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
