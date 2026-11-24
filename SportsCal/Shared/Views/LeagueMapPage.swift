//
//  LeagueMapPage.swift
//  SportsCal
//
//  Onboarding step 1 (3.5): "Where's your sport?". A dot map of the world with a
//  glowing spot for each place that has leagues, starter packs, and team/league
//  search, all filling one tray. Replaces the sport-tile grid (`PickSportPage`,
//  still reachable with `-OnboardingClassic YES` in debug builds).
//

import SwiftUI
import SportsCalModel
import NukeUI

/// Where the map is zoomed to.
private enum MapFocus: Equatable {
    case world
    case cluster(String)
    case hub(String)
}

/// Map units → points: `screen = mapPoint * scale + (tx, ty)`. Kept affine so the dots
/// and the hub buttons, animated separately, move exactly together.
private struct MapViewport: Equatable {
    var scale: CGFloat
    var tx: CGFloat
    var ty: CGFloat

    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + tx, y: p.y * scale + ty) }
}

struct LeagueMapPage: View {
    @Binding var sheetType: SheetType?
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var selection = LeagueMapSelection()
    @State private var focus: MapFocus = .world
    @State private var openHubID: String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var regionHubID: String?
    @State private var didSeed = false
    @State private var teamsPresented = false
    /// Bumped per hub to replay its flash (packs and team picks light their places up).
    @State private var flashes: [String: Int] = [:]
    /// Every competition each team plays in (`/teams/competitions`). Nil until loaded or
    /// on a server without the route; then `scheduleTeamLeagues` stands in.
    @State private var competitions: TeamCompetitionIndex?
    @State private var scheduleTeamLeagues: [String: [Leagues]] = [:]
    @State private var pageSize: CGSize = .zero
    @State private var mapFrame: CGRect = .zero

    private static let space = "leagueMapPage"
    private var isWide: Bool { pageSize.width >= 600 }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(2)
            map
                .zIndex(0)
            tray
                .zIndex(1)
        }
        .overlay(alignment: isWide ? .trailing : .bottom) {
            if !isWide, let hub = openHub {
                panel(hub)
                    .frame(height: compactPanelHeight)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { pageSize = $0 }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Skip", action: skip)
            }
        }
        #endif
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(isPresented: $teamsPresented) {
            PickTeamsPage(sheetType: $sheetType)
                .environment(appStorage)
                .environment(viewModel)
                .environment(favorites)
        }
        .task {
            if competitions == nil { competitions = await NetworkHandler.getTeamCompetitions() }
        }
        .task(id: viewModel.totalGames?.count ?? 0) {
            scheduleTeamLeagues = LeagueMap.teamLeagues(from: viewModel.totalGames ?? [])
        }
        .onAppear(perform: seed)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where's your sport?")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick a pack, search your team, or explore the map.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                #if os(macOS)
                // The onboarding sheet has no toolbar on the Mac.
                Spacer()
                Button("Skip", action: skip)
                #endif
            }
            // The search results hang below the field, so it draws above the packs row.
            if isWide {
                HStack(spacing: 10) {
                    searchField.frame(width: 250).zIndex(1)
                    packsRow
                }
                .zIndex(1)
            } else {
                searchField.zIndex(1)
                packsRow
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search a team or league", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.14)))
        .overlay(alignment: .topLeading) {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
                    .frame(width: isWide ? 360 : max(pageSize.width - 32, 0))
                    .offset(y: 46)
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { closePanel() }
        }
    }

    private var packsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(LeagueMap.packs) { pack in
                    let on = pack.isOn(in: selection.leagues)
                    Button {
                        togglePack(pack)
                    } label: {
                        Text("\(pack.emoji) \(pack.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
                            .overlay(Capsule().stroke(on ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pack.name)
                    .accessibilityValue(pack.leagues.map(LeagueMap.name).joined(separator: ", "))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: Search

    private struct TeamResult: Identifiable {
        let team: Team
        let leagues: [Leagues]
        var id: String { team.idTeam ?? team.strTeam ?? "" }
    }

    private func teamResults(_ term: String) -> [TeamResult] {
        var seen: Set<String> = []
        var matches: [TeamResult] = []
        for team in viewModel.teams {
            guard let name = team.strTeam, !name.isEmpty else { continue }
            let key = team.idTeam ?? name
            guard !seen.contains(key) else { continue }
            guard name.localizedCaseInsensitiveContains(term)
                    || (team.strTeamShort ?? "").caseInsensitiveCompare(term) == .orderedSame
                    || (team.strAlternate ?? "").localizedCaseInsensitiveContains(term) else { continue }
            seen.insert(key)
            matches.append(TeamResult(team: team, leagues: teamCompetitions(team)))
        }
        let lower = term.lowercased()
        return matches.sorted { l, r in
            // Teams whose name starts with the search, and teams we know the leagues of, first.
            let lp = (l.team.strTeam ?? "").lowercased().hasPrefix(lower), rp = (r.team.strTeam ?? "").lowercased().hasPrefix(lower)
            if lp != rp { return lp }
            if l.leagues.isEmpty != r.leagues.isEmpty { return !l.leagues.isEmpty }
            return (l.team.strTeam ?? "") < (r.team.strTeam ?? "")
        }
    }

    private var searchResults: some View {
        let term = query.trimmingCharacters(in: .whitespaces)
        let teams = Array(teamResults(term).prefix(5))
        let leagues = Array(LeagueMap.leagues(matching: term).prefix(8 - teams.count))
        return ScrollView {
            VStack(spacing: 0) {
                if teams.isEmpty && leagues.isEmpty {
                    Text("No team or league by that name yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(teams) { result in
                    resultRow(added: selection.containsTeam(result.team), addLabel: "Add", addedLabel: "Added") {
                        pickTeam(result)
                    } icon: {
                        crest(result.team, sport: result.leagues.first.map(SportType.init(league:)) ?? .soccer)
                    } title: {
                        Text(result.team.strTeam ?? "")
                    } subtitle: {
                        if !result.leagues.isEmpty {
                            Text(result.leagues.map(LeagueMap.name).joined(separator: " · "))
                        }
                    }
                }
                ForEach(leagues) { item in
                    resultRow(added: selection.contains(item.entry.league), addLabel: "Follow", addedLabel: "Following") {
                        pickLeague(item.entry.league, from: item.hub)
                    } icon: {
                        sportIcon(item.entry.sport, size: 30)
                    } title: {
                        Text(item.entry.name)
                    } subtitle: {
                        Text("\(item.hub.flag) \(item.hub.name)")
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 330)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private func resultRow(added: Bool, addLabel: String, addedLabel: String, action: @escaping () -> Void,
                           @ViewBuilder icon: () -> some View, @ViewBuilder title: () -> some View,
                           @ViewBuilder subtitle: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                VStack(alignment: .leading, spacing: 1) {
                    title()
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    subtitle()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(added ? addedLabel : addLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(added ? Color.secondary : Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    @ViewBuilder
    private func crest(_ team: Team, sport: SportType) -> some View {
        if let string = team.strTeamBadge, let url = URL(string: string) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 30, height: 30)
        } else {
            TeamLogo(abbreviation: String((team.strTeamShort ?? team.strTeam ?? "?").prefix(3)), sport: sport, size: 30)
        }
    }

    private func sportIcon(_ sport: SportType, size: CGFloat) -> some View {
        Image(systemName: sport.systemImage)
            .font(.system(size: size * 0.48))
            .foregroundStyle(Color.app(sport))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Color.app(sport).opacity(0.16)))
            .accessibilityHidden(true)
    }

    /// A team's leagues and cups: the server's index, else what the schedule shows it in.
    private func teamCompetitions(_ team: Team) -> [Leagues] {
        guard let id = team.idTeam else { return [] }
        if let known = competitions?.leagues(forTeam: id), !known.isEmpty { return known }
        return scheduleTeamLeagues[id] ?? []
    }

    private func pickTeam(_ result: TeamResult) {
        if !favorites.contains(team: result.team) { favorites.add(team: result.team) }
        selection.add(team: result.team, competitions: result.leagues)
        query = ""
        searchFocused = false
        flash(result.leagues.flatMap(LeagueMap.hubIDs(containing:)))
    }

    private func pickLeague(_ league: Leagues, from hub: LeagueMapHub) {
        selection.add(league)
        query = ""
        searchFocused = false
        open(hub)
    }

    // MARK: Map

    private var liveLeagues: Set<Leagues> {
        Set(viewModel.allLiveEvents.compactMap { $0.idLeague.flatMap { Int($0) }.flatMap(Leagues.init(rawValue:)) })
    }

    private var openHub: LeagueMapHub? { openHubID.flatMap(LeagueMap.hub(id:)) }

    private var map: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let viewport = viewport(for: focus, in: size)
            ZStack {
                // Tapping open sea closes the list.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { if openHubID != nil { closePanel() } }
                LeagueMapLayer(viewport: viewport,
                               baseScale: baseViewport(in: size).scale,
                               hubs: LeagueMap.hubs,
                               picked: selection.leagues,
                               regionHubID: regionHubID,
                               selectedHubID: openHubID,
                               flashes: flashes,
                               reduceMotion: reduceMotion) { hub in
                    tap(hub, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottomLeading) { worldwideButton.padding(12) }
            .overlay(alignment: .bottomTrailing) {
                if focus != .world {
                    Button {
                        closePanel()
                        animate { focus = .world }
                    } label: {
                        Label("Whole map", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .trailing) {
                if isWide, let hub = openHub {
                    panel(hub)
                        .frame(width: widePanelWidth(size))
                        .padding(.vertical, 8)
                        .padding(.trailing, 12)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { mapFrame = $0 }
        .frame(minHeight: 180)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("League map")
    }

    private var worldwideButton: some View {
        let followed = LeagueMap.worldwide.followedCount(in: selection.leagues)
        return Button {
            open(LeagueMap.worldwide)
        } label: {
            HStack(spacing: 6) {
                Text("🌐 Worldwide").fontWeight(.semibold).foregroundStyle(.primary)
                Text(followed > 0 ? "\(followed) followed" : "World Cup, F1, tennis…")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(openHubID == LeagueMap.worldwide.id ? Color.accentColor : Color.secondary.opacity(0.25)))
            .keyframeAnimator(initialValue: 1.0, trigger: flashes[LeagueMap.worldwide.id] ?? 0) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(reduceMotion ? 1 : 1.12, duration: 0.18)
                CubicKeyframe(1, duration: 0.32)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LeagueMap.worldwide.accessibilityLabel(followed: followed))
        .accessibilityHint("World Cup, Formula 1, tennis and international cricket")
    }

    private func baseViewport(in size: CGSize) -> MapViewport {
        let map = LeagueMap.size
        let scale = max(min(size.width / map.width, size.height / map.height), 0.01)
        return MapViewport(scale: scale, tx: (size.width - map.width * scale) / 2,
                           ty: (size.height - map.height * scale) / 2)
    }

    private func viewport(for focus: MapFocus, in size: CGSize) -> MapViewport {
        let base = baseViewport(in: size)
        let point: CGPoint, scale: CGFloat
        switch focus {
        case .world:
            return base
        case .cluster(let id):
            guard let cluster = LeagueMap.clusters.first(where: { $0.id == id }) else { return base }
            point = cluster.centre
            scale = max(base.scale * 1.6, cluster.scale(forSpacing: 50))
        case .hub(let id):
            guard let hub = LeagueMap.hub(id: id), let p = hub.point else { return base }
            point = p
            scale = hubScale(id, base: base.scale)
        }
        let visible = visibleMapRect(in: size)
        return MapViewport(scale: scale, tx: visible.midX - point.x * scale, ty: visible.midY - point.y * scale)
    }

    private func hubScale(_ id: String, base: CGFloat) -> CGFloat {
        var scale = max(base * 1.6, 2.8)
        if let cluster = LeagueMap.cluster(containing: id) { scale = max(scale, cluster.scale(forSpacing: 50)) }
        return scale
    }

    /// The part of the map the list doesn't cover, in map coordinates, so a zoomed spot
    /// lands where it can be seen.
    private func visibleMapRect(in size: CGSize) -> CGRect {
        guard openHubID != nil else { return CGRect(origin: .zero, size: size) }
        if isWide {
            return CGRect(x: 0, y: 0, width: max(size.width - widePanelWidth(size) - 12, 80), height: size.height)
        }
        let panelTop = pageSize.height - compactPanelHeight
        let bottom = min(size.height, max(panelTop - mapFrame.minY, 70))
        return CGRect(x: 0, y: 0, width: size.width, height: bottom)
    }

    private func widePanelWidth(_ size: CGSize) -> CGFloat { min(320, size.width * 0.5) }
    private var compactPanelHeight: CGFloat { min(pageSize.height * 0.58, 560) }

    private func tap(_ hub: LeagueMapHub, in size: CGSize) {
        searchFocused = false
        let current = viewport(for: focus, in: size).scale
        if let cluster = LeagueMap.cluster(containing: hub.id), !voiceOver,
           current * cluster.minimumSpacing < 44, focus != .cluster(cluster.id) {
            // Too tight to tell the spots apart: zoom in first, open on the next tap.
            closePanel()
            animate { focus = .cluster(cluster.id) }
            return
        }
        open(hub)
    }

    private func open(_ hub: LeagueMapHub) {
        searchFocused = false
        animate {
            openHubID = hub.id
            if hub.point != nil { focus = .hub(hub.id) }
        }
    }

    private func closePanel() {
        guard openHubID != nil else { return }
        animate {
            openHubID = nil
            // Keep the zoom, but re-centre now the list is gone.
        }
    }

    private func animate(_ body: () -> Void) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.12), body)
    }

    // MARK: Panel

    private func panel(_ hub: LeagueMapHub) -> some View {
        LeagueMapPanel(hub: hub, picked: selection.leagues, live: liveLeagues, isWide: isWide) { league in
            selection.toggle(league)
        } toggleAll: {
            let allOn = hub.leagues.allSatisfy { selection.contains($0.league) }
            for entry in hub.leagues {
                if allOn { selection.remove(entry.league) } else { selection.add(entry.league) }
            }
        } done: {
            closePanel()
        }
    }

    // MARK: Tray

    private var tray: some View {
        Group {
            if isWide {
                HStack(spacing: 12) {
                    pickedRow
                    continueButton.frame(width: 300)
                }
            } else {
                VStack(spacing: 10) {
                    pickedRow
                    continueButton
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var pickedRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if selection.isEmpty {
                    Text("Leagues you follow show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 5)
                }
                ForEach(selection.teams, id: \.self) { team in
                    pill(Text(team.strTeam ?? ""), icon: Image(systemName: "star.fill"), tint: .yellow) {
                        selection.remove(team: team)
                        favorites.remove(team: team)
                    }
                    .accessibilityLabel("\(team.strTeam ?? ""), team")
                }
                ForEach(selection.leagues, id: \.self) { league in
                    let sport = SportType(league: league)
                    pill(Text(LeagueMap.name(league)), icon: Image(systemName: sport.systemImage), tint: Color.app(sport)) {
                        selection.remove(league)
                    }
                    .accessibilityLabel(LeagueMap.name(league))
                }
            }
        }
        .frame(minHeight: 30)
        .animation(reduceMotion ? nil : .default, value: selection)
    }

    private func pill(_ title: Text, icon: Image, tint: Color, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                icon.foregroundStyle(tint).imageScale(.small)
                title.foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Removes it")
    }

    private var continueButton: some View {
        Button(action: continueTapped) {
            Text(selection.continueTitle)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selection.isEmpty)
    }

    // MARK: Actions

    /// First appearance: an install that already shows something starts from what it
    /// shows (re-running onboarding shouldn't wipe it); a fresh one from the region's picks.
    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        let region = Locale.current.region?.identifier
        regionHubID = LeagueMap.regionHubID(forRegion: region)
        let current = currentlyShownLeagues()
        let leagues = current.isEmpty ? LeagueMap.regionDefaults(forRegion: region) : current
        leagues.forEach { selection.add($0) }
        #if DEBUG
        // Screenshot hooks: `-LeagueMapDemoHub GB` opens a place, `-LeagueMapDemoSearch Arsenal` searches.
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "LeagueMapDemoHub"), let hub = LeagueMap.hub(id: id) {
            Task { @MainActor in open(hub) }
        }
        if let term = defaults.string(forKey: "LeagueMapDemoSearch") {
            query = term
        }
        #endif
    }

    /// Leagues on the map the current settings already show.
    private func currentlyShownLeagues() -> [Leagues] {
        guard !appStorage.enabledSports.isEmpty else { return [] }
        let hidden = Set(appStorage.hiddenCompetitions)
        var seen: Set<Leagues> = []
        return LeagueMap.allHubs.flatMap(\.leagues).map(\.league).filter { league in
            guard seen.insert(league).inserted, !hidden.contains(league.leagueName) else { return false }
            switch league {
            case .nfl: return appStorage.shouldShowNFL
            case .ncaaf: return appStorage.shouldShowCFB
            case .nba: return appStorage.shouldShowNBA
            case .wnba: return appStorage.shouldShowWNBA
            case .ncaaMBBTournament: return appStorage.shouldShowCBB
            case .FIFA_World_Cup: return appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup
            default: return appStorage.userShouldShow(SportType(league: league))
            }
        }
    }

    private func togglePack(_ pack: LeagueMapPack) {
        let on = pack.isOn(in: selection.leagues)
        searchFocused = false
        closePanel()
        animate { focus = .world }
        for league in pack.leagues {
            if on { selection.remove(league) } else { selection.add(league) }
        }
        if !on { flash(pack.hubIDs) }
    }

    private func flash(_ hubIDs: [String]) {
        for id in Set(hubIDs) { flashes[id, default: 0] += 1 }
    }

    private func continueTapped() {
        appStorage.applyOnboardingSelection(Set(selection.leagues))
        viewModel.filterSports(force: true)
        viewModel.getInfo()
        teamsPresented = true
    }

    /// Moves on without applying the map. An install with nothing switched on gets the
    /// region's picks, so the app doesn't open empty.
    private func skip() {
        if appStorage.enabledSports.isEmpty && !appStorage.shouldShowWorldCup {
            appStorage.applyOnboardingSelection(Set(LeagueMap.regionDefaults(forRegion: Locale.current.region?.identifier)))
            viewModel.filterSports(force: true)
        }
        viewModel.getInfo()
        teamsPresented = true
    }
}

// MARK: - Map layer

/// The dots and the spots, drawn for one viewport. Animatable, so a zoom interpolates
/// the viewport and redraws every frame instead of scaling a bitmap.
private struct LeagueMapLayer: View, Animatable {
    var viewport: MapViewport
    let baseScale: CGFloat
    let hubs: [LeagueMapHub]
    let picked: [Leagues]
    let regionHubID: String?
    let selectedHubID: String?
    let flashes: [String: Int]
    let reduceMotion: Bool
    let onTap: (LeagueMapHub) -> Void

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(viewport.scale, AnimatablePair(viewport.tx, viewport.ty)) }
        set {
            viewport.scale = newValue.first
            viewport.tx = newValue.second.first
            viewport.ty = newValue.second.second
        }
    }

    private var zoom: CGFloat { max(viewport.scale / max(baseScale, 0.01), 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // Dots grow a little with zoom but stay dots, so the spots stand out.
                let radius = min(0.95 * viewport.scale, max(0.95 * baseScale, 2.6))
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -radius, dy: -radius)
                var path = Path()
                for dot in LeagueMap.landDots {
                    let p = viewport.point(dot)
                    guard bounds.contains(p) else { continue }
                    path.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                }
                context.fill(path, with: .color(.primary.opacity(0.17)))
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            ForEach(hubs) { hub in
                if let point = hub.point {
                    let followed = hub.followedCount(in: picked)
                    LeagueMapHubDot(hub: hub,
                                    coreRadius: hub.radius * baseScale * pow(zoom, 0.55),
                                    followed: followed,
                                    pulses: hub.id == regionHubID && followed == 0 && !reduceMotion,
                                    isSelected: hub.id == selectedHubID,
                                    showsFlag: zoom >= 2,
                                    flash: flashes[hub.id] ?? 0,
                                    reduceMotion: reduceMotion) {
                        onTap(hub)
                    }
                    .position(viewport.point(point))
                }
            }
        }
    }
}

private struct LeagueMapHubDot: View {
    let hub: LeagueMapHub
    let coreRadius: CGFloat
    let followed: Int
    let pulses: Bool
    let isSelected: Bool
    let showsFlag: Bool
    let flash: Int
    let reduceMotion: Bool
    let action: () -> Void

    private var color: Color { hub.sport.map(Color.app) ?? .accentColor }
    private var isOn: Bool { followed > 0 }

    var body: some View {
        let core = coreRadius * 2
        let halo = core * 1.7
        let target = max(44, halo)
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(isOn ? 0.32 : 0.16))
                    .frame(width: halo, height: halo)
                    // Where you are: breathes until something there is followed.
                    .phaseAnimator(pulses ? [1.0, 1.5] : [1.0]) { content, phase in
                        content.scaleEffect(phase)
                    } animation: { _ in .easeInOut(duration: 0.9) }
                // Flash ring: replays when a pack or team adds something here.
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: halo, height: halo)
                    .keyframeAnimator(initialValue: FlashValue(), trigger: flash) { content, value in
                        content.scaleEffect(value.scale).opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0.95, duration: 0.05)
                            LinearKeyframe(0, duration: 0.85)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.05)
                            CubicKeyframe(reduceMotion ? 1 : 2.2, duration: 0.85)
                        }
                    }
                Circle()
                    .fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.background))
                    .overlay(Circle().stroke(color, lineWidth: isSelected ? 2.6 : 1.6))
                    .frame(width: core, height: core)
                Text("\(hub.leagues.count)")
                    .font(.system(size: max(7, coreRadius * 0.95), weight: .bold).monospacedDigit())
                    .foregroundStyle(isOn ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                if showsFlag {
                    Text(hub.flag)
                        .font(.system(size: 13))
                        .offset(y: -(halo / 2 + 9))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: target, height: target)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hub.accessibilityLabel(followed: followed))
        .accessibilityHint("Shows its leagues")
    }

    private struct FlashValue {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}

// MARK: - Panel

/// One place's leagues with follow toggles.
private struct LeagueMapPanel: View {
    let hub: LeagueMapHub
    let picked: [Leagues]
    let live: Set<Leagues>
    let isWide: Bool
    let toggle: (Leagues) -> Void
    let toggleAll: () -> Void
    let done: () -> Void

    var body: some View {
        let followed = hub.followedCount(in: picked)
        let allOn = followed == hub.leagues.count
        VStack(spacing: 0) {
            if !isWide {
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            }
            HStack(spacing: 10) {
                Text(hub.flag).font(.system(size: 28)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(hub.name).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    Text(subtitle(followed: followed)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(allOn ? "Clear" : "Follow all", action: toggleAll)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .padding(.top, isWide ? 16 : 10)
            .padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hub.leagues) { entry in
                        row(entry)
                    }
                }
                .padding(.horizontal, 18)
            }
            Button(action: done) {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(4)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.3), radius: 20, y: isWide ? 4 : -6)
        .accessibilityElement(children: .contain)
        #if os(macOS)
        .onExitCommand(perform: done)
        #endif
    }

    private func subtitle(followed: Int) -> String {
        let count = "\(hub.leagues.count) \(hub.leagues.count == 1 ? "league" : "leagues")"
        return followed > 0 ? "\(count) · \(followed) followed" : count
    }

    private func row(_ entry: LeagueMapEntry) -> some View {
        let on = picked.contains(entry.league)
        let isLive = live.contains(entry.league)
        return Button {
            toggle(entry.league)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.sport.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.app(entry.sport))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.app(entry.sport).opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        if isLive {
                            Text("● LIVE").font(.caption2.weight(.bold)).foregroundStyle(.red)
                        }
                    }
                    Text(entry.season).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
        .accessibilityLabel(isLive ? "\(entry.name), live now" : entry.name)
        .accessibilityValue(on ? "Following" : "Not following")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    NavigationStack {
        LeagueMapPage(sheetType: .constant(.none))
    }
    .environment(storage)
    .environment(viewModel)
    .environment(Favorites())
}
