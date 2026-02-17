//
//  Tips.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/17/26.
//

import TipKit

struct CalendarFavoritesTip: Tip {
    var title: Text {
        Text("Filter to Favorites")
    }
    var message: Text? {
        Text("Tap to show only your favorite teams on the calendar.")
    }
    var image: Image? {
        Image(systemName: "star.fill")
    }
}

struct LiveActivityTip: Tip {
    var title: Text {
        Text("Follow Live Games")
    }
    var message: Text? {
        Text("Auto-follow upcoming games to get a Live Activity when they start.")
    }
    var image: Image? {
        Image(systemName: "clock.badge")
    }
}

struct SportFilterTip: Tip {
    var title: Text {
        Text("Filter by Sport")
    }
    var message: Text? {
        Text("Tap a sport chip to quickly filter your view.")
    }
    var image: Image? {
        Image(systemName: "line.3.horizontal.decrease.circle")
    }
}
