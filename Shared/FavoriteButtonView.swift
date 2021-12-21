//
//  FavoriteButtonView.swift
//  SportsCal
//
//  Created by Umar Haroon on 12/19/21.
//

import SwiftUI

struct FavoriteMenu: View {
    var game: Game?
    @EnvironmentObject var favorites: Favorites
    var body: some View {
        Menu {
            Button {
                if let game = game {
                    if favorites.contains(game) {
                        favorites.remove(game.home)
                    } else {
                        favorites.add(game.home)
                    }
                }
            } label: {
                if let game = game {
                    if favorites.containsHome(game.home) {
                        Text("Remove \(game.home) as favorite")
                    } else {
                        Text("Set \(game.home) as favorite")
                    }
                }
            }
            if game?.sport != .F1 {
                Button {
                    if let game = game {
                        if favorites.contains(game) {
                            favorites.remove(game.away)
                        } else {
                            favorites.add(game.away)
                        }
                    }
                } label: {
                    if let game = game {
                        if favorites.containsAway(game.away) {
                            Text("Remove \(game.away) as favorite")
                        } else {
                            Text("Set \(game.away) as favorite")
                        }
                    } else {
                        Text("unsure path")
                    }
                }
            }
        } label: {
            if let game = game {
                if favorites.contains(game) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: "star")
                }
            } else {
                Image(systemName: "star")
                
            }
        }
    }
}

struct FavoriteButtonView_Previews: PreviewProvider {
    static var previews: some View {
        FavoriteMenu()
    }
}
