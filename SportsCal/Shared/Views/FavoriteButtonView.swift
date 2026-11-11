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
    @Environment(Favorites.self) private var favorites
    var body: some View {
        Menu {
            Button {
                if let game = game {
                    if favorites.contains(game) {
                        favorites.remove(game, home: true)
                    } else {
                        favorites.add(game, home: true)
                    }
                }
            } label: {
                if let game = game {
                    if favorites.contains(game, home: true) {
                        Text("Remove \(game.strHomeTeam) as favorite")
                    } else {
                        Text("Set \(game.strHomeTeam) as favorite")
                    }
                }
            }
                Button {
                    if let game = game {
                        if favorites.contains(game) {
                            favorites.remove(game, home: false)
                        } else {
                            favorites.add(game, home: false)
                        }
                    }
                } label: {
                    if let game = game {
                        if favorites.contains(game, home: false) {
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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: favorites.teams)
    }
}

#Preview {
    @Previewable @State var favorites = Favorites()
    FavoriteMenu()
        .environment(favorites)
}
