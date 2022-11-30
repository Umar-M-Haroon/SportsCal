//
//  FavoriteButtonView.swift
//  SportsCal
//
//  Created by Umar Haroon on 12/19/21.
//

import SwiftUI
import SportsCalModel
struct FavoriteMenu: View {
    var game: Game?
    @EnvironmentObject var favorites: Favorites
    var body: some View {
        Menu {
            Button {
                if let game = game {
                    if favorites.contains(game) {
                        favorites.remove(game.strHomeTeam)
                    } else {
                        favorites.add(game.strHomeTeam)
                    }
                }
            } label: {
                if let game = game {
                    if favorites.containsHome(game.strHomeTeam) {
                        Text("Remove \(game.strHomeTeam) as favorite")
                    } else {
                        Text("Set \(game.strHomeTeam) as favorite")
                    }
                }
            }
                Button {
                    if let game = game {
                        if favorites.contains(game) {
                            favorites.remove(game.strAwayTeam)
                        } else {
                            favorites.add(game.strAwayTeam)
                        }
                    }
                } label: {
                    if let game = game {
                        if favorites.containsAway(game.strAwayTeam) {
                            Text("Remove \(game.strAwayTeam) as favorite")
                        } else {
                            Text("Set \(game.strAwayTeam) as favorite")
                        }
                    } else {
                        Text("unsure path")
                    }
                }
        } label: {
            if let game = game {
                if favorites.contains(game) {
                    Label("Favorites", systemImage: "star.fill")
                        .tint(.yellow)
                } else {
                    Label("Favorites", systemImage: "star")
                }
            } else {
                Label("Favorites", systemImage: "star")
            }
        }
    }
}

struct FavoriteButtonView_Previews: PreviewProvider {
    static var previews: some View {
        FavoriteMenu()
    }
}
