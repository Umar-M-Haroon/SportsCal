//
//  GameGridView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

import SwiftUI

struct GameGridView: View {
    @EnvironmentObject var storage: UserDefaultStorage
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var viewModel: GameViewModel
    
    @State private var sheetType: SheetType? = nil
    @State var shouldShowSportsCalProAlert: Bool = false
    var body: some View {
        Grid {
            ForEach(viewModel.sortedGames, id: \.key) { (key, value) in
                GroupBox {
                    ForEach(value.chunked(into: 2), id: \.self) { games in
                        HStack {
                                ForEach(games) { game in
                                    GroupBox {
                                    GameView(game: game)
                                        .environmentObject(viewModel)
                                        .environmentObject(favorites)
                                        .environmentObject(storage)
                                    }
                                }
                        }
                    }
                } label: {
                    Text(key.formatted(format: viewModel.appStorage.dateFormat, isRelative: viewModel.appStorage.useRelativeValue))
                }
            }
        }
        .padding(40)
    }
}

struct GameGridView_Previews: PreviewProvider {
    static var previews: some View {
        GameGridView()
            .environmentObject(Favorites())
            .environmentObject(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
            .environmentObject(UserDefaultStorage())
    }
}
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
