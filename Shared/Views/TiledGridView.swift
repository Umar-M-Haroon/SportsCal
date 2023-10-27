//
//  TiledGridView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 6/29/23.
//

import SwiftUI

struct TiledGridView: View {
    let systemNames: [String] = ["basketball", "hockey.puck.fill", "baseball", "football.fill", "soccerball.inverse"]
    var body: some View {
        GeometryReader { geometry in
            let columns = Int(geometry.size.width / 50)
            let rows = Int(geometry.size.height / 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 10) {
                ForEach(0..<(rows * columns), id: \.self) { index in
                    let systemName = systemNames[index % systemNames.count]
                    
                    Image(systemName: systemName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .padding(25)
                        .foregroundStyle(.tertiary)
                }
            }
        }
//        .rotationEffect(.degrees(45))
//        .ignoresSafeArea(.all)
    }
}

//#Preview {
//    TiledGridView(systemNames: ["basketball", "hockey.puck.fill", "baseball", "football.fill", "soccerball.inverse"])
//}
