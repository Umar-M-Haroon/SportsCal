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
    @State var selectedDate: DateComponents? = nil
    @Binding var sheetType: SheetType?
    @Binding var showFavoritesOnly: Bool
    @Binding var navigateToDate: Date?
    @Binding var sportFilter: SportChipFilter

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.delegate = context.coordinator
        calendarView.locale = Locale.current
        calendarView.wantsDateDecorations = true
        calendarView.visibleDateComponents = Calendar.current.dateComponents([.day, .month, .year], from: .now)
        calendarView.fontDesign = .rounded
        calendarView.overrideUserInterfaceStyle = storage.appTheme == .ambient ? .dark : .unspecified
        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        uiView.overrideUserInterfaceStyle = storage.appTheme == .ambient ? .dark : .unspecified
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
        if let selectedDate {
            context.coordinator.presentSheetForSelectedDate(dateComponents: selectedDate)
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
        return CalendarCoordinator(games: groupedGames, liveGames: groupedLiveGames, date: $selectedDate, sheet: $sheetType, favorites: favorites.teams, showFavoritesOnly: showFavoritesOnly)
    }

    typealias UIViewType = UICalendarView

}

class CalendarCoordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {

    var games: [DateComponents? : [Game]]
    var liveGames: [DateComponents? : [Game]]
    @Binding var selectedDate: DateComponents?
    @Binding var sheetType: SheetType?
    var favorites: Set<String>
    var showFavoritesOnly: Bool
    var previousGameDates: Set<DateComponents> = []

    init(games: [DateComponents? : [Game]], liveGames: [DateComponents? : [Game]], date: Binding<DateComponents?>, sheet: Binding<SheetType?>, favorites: Set<String>, showFavoritesOnly: Bool) {
        self.games = games
        self._selectedDate = date
        self._sheetType = sheet
        self.favorites = favorites
        self.liveGames = liveGames
        self.showFavoritesOnly = showFavoritesOnly
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        selectedDate = dateComponents
        presentSheetForSelectedDate(dateComponents: dateComponents)
    }

    func presentSheetForSelectedDate(dateComponents: DateComponents?) {
        guard let dateComponents,
              let date = Calendar.current.date(from: dateComponents) else { return }
        let comps = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: date)
        var liveSorted: [Game] = []
        var listSorted: [Dictionary<DateComponents, [Game]>.Element] = []
        if let liveGames = liveGames[comps] {
            liveSorted = liveGames
        }
        if let listGames = games[comps] {
            let groupDic = Dictionary(grouping: listGames) { game -> DateComponents in
                let gameDate = game.standardDate ?? .now
                let date2 = Calendar.current.dateComponents([.day, .year, .month, .calendar], from: gameDate)
                return date2
            }
            let sorted = groupDic.sorted(by: {
                return $0.key.date! < $1.key.date!
            })
            listSorted = sorted
        }

        sheetType = .listDetail(games: listSorted, liveGames: liveSorted)
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
        if let selectedDate {
            result.append(selectedDate)
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
#endif
