//
//  CalendarViewRepresentable.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

#if os(iOS)
import SwiftUI
import SportsCalModel
import UIKit

struct CalendarViewRepresentable: UIViewRepresentable {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage
    @Binding var showFavoritesOnly: Bool
    @Binding var navigateToDate: Date?
    @Binding var sportFilter: SportChipFilter
    /// The day shown beside the calendar in wide layouts; highlighted here.
    /// `nil` in compact layouts, where a tap opens a sheet and the highlight clears.
    var selectedDay: DateComponents?
    /// Called when the user taps a day.
    var onSelectDay: (DateComponents) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        calendarView.overrideUserInterfaceStyle = storage.effectiveAppTheme == .ambient ? .dark : .unspecified
        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        uiView.overrideUserInterfaceStyle = storage.effectiveAppTheme == .ambient ? .dark : .unspecified
        var gamesToUse = viewModel.calendarGames ?? []
        if showFavoritesOnly {
            gamesToUse = gamesToUse.filter { favorites.contains($0) }
        }
        gamesToUse = gamesToUse.filter { sportFilter.matches($0) }
        var dayComponents = DayComponentsCache()
        let newGames = Dictionary(grouping: gamesToUse, by: { dayComponents.components(for: $0.standardDate) })
        let newLiveGames = Dictionary(grouping: viewModel.allLiveEvents, by: { dayComponents.components(for: $0.standardDate) })

        let newDateSet = Set(newGames.keys.compactMap { $0 })
        let componentsToReload = context.coordinator.reloadApplicableDecorations(newDates: newDateSet)

        context.coordinator.games = newGames
        context.coordinator.liveGames = newLiveGames
        context.coordinator.favorites = favorites.teams
        context.coordinator.showFavoritesOnly = showFavoritesOnly
        context.coordinator.onSelectDay = onSelectDay
        context.coordinator.keepsSelection = selectedDay != nil
        // Keep the highlight in step with the inline day (wide layouts only).
        // Updates never present anything: a day is opened only by a tap, in
        // `dateSelection(_:didSelectDate:)`.
        if let selection = uiView.selectionBehavior as? UICalendarSelectionSingleDate,
           !Self.isSameDay(selection.selectedDate, selectedDay) {
            selection.setSelected(selectedDay, animated: false)
        }
        if let navigateToDate {
            uiView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: navigateToDate)
            DispatchQueue.main.async { self.navigateToDate = nil }
        }
        // Non-animated: a reload spans every date that has games (hundreds after a
        // schedule fetch), and animating that many decoration cells at once was pure
        // main-thread cost for an effect nobody sees mid-scroll.
        uiView.reloadDecorations(forDateComponents: componentsToReload, animated: false)
    }

    func makeCoordinator() -> CalendarCoordinator {
        let filteredCalendarGames = (viewModel.calendarGames ?? []).filter { sportFilter.matches($0) }
        var dayComponents = DayComponentsCache()
        let groupedGames = Dictionary(grouping: filteredCalendarGames, by: { dayComponents.components(for: $0.standardDate) })
        let groupedLiveGames = Dictionary(grouping: viewModel.allLiveEvents, by: { dayComponents.components(for: $0.standardDate) })
        return CalendarCoordinator(games: groupedGames, liveGames: groupedLiveGames, favorites: favorites.teams, showFavoritesOnly: showFavoritesOnly, onSelectDay: onSelectDay)
    }

    typealias UIViewType = UICalendarView

    private static func isSameDay(_ a: DateComponents?, _ b: DateComponents?) -> Bool {
        a?.year == b?.year && a?.month == b?.month && a?.day == b?.day
    }
}

class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {

    var games: [DateComponents? : [Game]]
    var liveGames: [DateComponents? : [Game]]
    var favorites: Set<String>
    var showFavoritesOnly: Bool
    var previousGameDates: Set<DateComponents> = []
    var onSelectDay: (DateComponents) -> Void
    /// Wide layouts keep the tapped day highlighted; compact ones clear it so the
    /// same day can be tapped again after its sheet closes.
    var keepsSelection = false
    private var lastSelectedDay: DateComponents?

    init(games: [DateComponents? : [Game]], liveGames: [DateComponents? : [Game]], favorites: Set<String>, showFavoritesOnly: Bool, onSelectDay: @escaping (DateComponents) -> Void) {
        self.games = games
        self.favorites = favorites
        self.liveGames = liveGames
        self.showFavoritesOnly = showFavoritesOnly
        self.onSelectDay = onSelectDay
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        guard let dateComponents else { return }
        lastSelectedDay = dateComponents
        onSelectDay(dateComponents)
        if !keepsSelection {
            selection.setSelected(nil, animated: true)
        }
    }

    @MainActor func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = Calendar.current.date(from: dateComponents) else { return nil }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)

        if let filteredGames = games[comps] {
            let sportTypes = Set(filteredGames.compactMap { game -> SportType? in
                guard let league = game.idLeague,
                      let leagueInt = Int(league),
                      let foundLeague = Leagues(rawValue: leagueInt)
                      else {
                    return nil
                }
                return SportType(league: foundLeague)
            })
            if sportTypes.isEmpty {
                return nil
            }
            let showFavorites = filteredGames.contains(where: { favorites.contains($0.strAwayTeam) || favorites.contains($0.strHomeTeam) })

            return .customView {
                DecorationViewFactory.make(sportTypes: sportTypes, showFavorites: showFavorites)
            }
        }
        return nil
    }

    func reloadApplicableDecorations(newDates: Set<DateComponents>) -> [DateComponents] {
        let allDates = previousGameDates.union(newDates)
        previousGameDates = newDates
        var result = Array(allDates)
        result.append(Date.now.toComponents())
        if let lastSelectedDay {
            result.append(lastSelectedDay)
        }
        return result
    }
}

/// Memoizes `Date` → day `DateComponents` for one grouping pass.
///
/// `updateUIView` regroups every calendar game on each SwiftUI update, and
/// `Calendar.dateComponents` allocates on every call — tens of thousands of them per
/// pass, on the main thread, inside a `UIViewRepresentable` update. The games span only
/// a few hundred distinct days, so the conversion is done once per day and looked up by
/// an integer index afterwards. Output is identical to calling `toComponents()` directly.
struct DayComponentsCache {
    private var cache: [Int: DateComponents] = [:]
    private let timeZone = Calendar.current.timeZone

    mutating func components(for date: Date?) -> DateComponents? {
        guard let date else { return nil }
        let offset = timeZone.secondsFromGMT(for: date)
        let dayIndex = Int(floor((date.timeIntervalSince1970 + Double(offset)) / 86_400))
        if let cached = cache[dayIndex] { return cached }
        let components = date.toComponents()
        cache[dayIndex] = components
        return components
    }
}

/// Builds calendar day decorations as plain UIKit views backed by cached images.
///
/// Each decoration used to be a `UIHostingController` hosting an `HStack` of up to nine
/// SF Symbols, constructed fresh for every decorated date. `UICalendarView` sizes
/// decorations during layout, so a month's worth meant dozens of SwiftUI hosts plus
/// repeated SF Symbol rasterisation on the main thread — Sentry caught it as multi-second
/// `CGSVGDocumentCreateFromData` / `SVGParser` hangs under
/// `UICalendarViewDecoration _referenceHeightForTraitCollection`. Rendering each symbol
/// once and reusing the `UIImage` keeps the visuals identical and makes a reload cheap.
@MainActor
enum DecorationViewFactory {
    private static var imageCache: [String: UIImage] = [:]

    private static func image(systemName: String, size: CGFloat, color: UIColor) -> UIImage? {
        // Keyed on the colour's component description, not its hash: a hash collision
        // would silently hand back a dot in the wrong sport's colour.
        let key = "\(systemName)|\(size)|\(color)"
        if let cached = imageCache[key] { return cached }
        let config = UIImage.SymbolConfiguration(pointSize: size)
        guard let image = UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        imageCache[key] = image
        return image
    }

    static func make(sportTypes: Set<SportType>, showFavorites: Bool) -> UIView {
        // Matches DecorationView: symbols shrink once the row gets crowded.
        let iconSize: CGFloat = sportTypes.count >= 5 ? 6 : 8
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center

        for sport in SportType.allCases where sportTypes.contains(sport) {
            guard let image = image(systemName: sport.systemImage, size: iconSize, color: UIColor(sport.color)) else { continue }
            stack.addArrangedSubview(UIImageView(image: image))
        }
        if showFavorites, let star = image(systemName: "star.fill", size: iconSize, color: .systemYellow) {
            stack.addArrangedSubview(UIImageView(image: star))
        }
        return stack
    }
}

extension Date {
    func toComponents() -> DateComponents {
        Calendar.current.dateComponents([.day, .month, .year, .calendar], from: self)
    }
}

/// One calendar day's games, grouped the way the day list shows them. Shared by
/// the sheet (compact) and the inline day beside the calendar (wide).
struct CalendarDayGames {
    let listGames: [(key: DateComponents, value: [Game])]
    let liveGames: [Game]

    init(day: DateComponents, games: [Game], liveGames: [Game]) {
        let calendar = Calendar.current
        guard let date = calendar.date(from: day) else {
            listGames = []
            self.liveGames = []
            return
        }
        let dayGames = games.filter { game in
            guard let gameDate = game.standardDate else { return false }
            return calendar.isDate(gameDate, inSameDayAs: date)
        }
        self.liveGames = liveGames.filter { game in
            guard let gameDate = game.standardDate else { return false }
            return calendar.isDate(gameDate, inSameDayAs: date)
        }
        let grouped = Dictionary(grouping: dayGames) { game in
            calendar.dateComponents([.day, .year, .month, .calendar], from: game.standardDate ?? .now)
        }
        listGames = grouped.sorted { ($0.key.date ?? .distantPast) < ($1.key.date ?? .distantPast) }
    }
}
#endif
