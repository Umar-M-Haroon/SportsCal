//
//  ThemeSettingsView.swift
//  SportsCal
//
//  Settings → Themes: accent color (curated, team, custom) and, on iOS, the
//  alternate app icon. Anyone can open it and preview a theme live; applying a
//  non-default accent or icon needs Pro (`ProFeature.themes`) and routes through
//  the paywall with the `theme` trigger.
//

import SwiftUI
import SportsCalModel

struct ThemeSettingsView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    private var store: ThemeStore { .shared }
    private var subscriptions: SubscriptionManager { .shared }
    private var isEntitled: Bool { subscriptions.canUse(.themes) }

    /// What the preview shows. For Pro users this tracks the applied selection;
    /// free users can browse freely without changing anything.
    @State private var previewAccent: AppAccent = ThemeStore.shared.accent
    @State private var customColor: Color = Color(accentHex: ThemeStore.shared.customHex)
    @State private var teamCandidates: [TeamAccentCandidate] = []
    @State private var showPaywall = false
    #if os(iOS)
    @State private var currentIcon: AppIconChoice = .standard
    @State private var previewIcon: AppIconChoice?
    @State private var iconError: String?
    #endif

    var body: some View {
        Form {
            previewSection
            accentSection
            #if os(iOS)
            if AppIconChoice.supported {
                iconSection
            }
            #endif
            if !isEntitled {
                unlockSection
            }
        }
        .navigationTitle("Themes")
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .task {
            teamCandidates = TeamAccentCandidate.collect(
                favoriteIDs: favorites.teamIDs,
                games: (viewModel.totalGames ?? []) + viewModel.liveEvents
            )
            #if os(iOS)
            currentIcon = AppIconChoice.current
            #endif
        }
        .onChange(of: customColor) { _, newValue in
            previewAccent = .custom
            commitIfEntitled(.custom, customHex: newValue.accentHexValue)
        }
        .onChange(of: subscriptions.isPro) { _, isPro in
            // Bought Pro from here: apply what they were previewing.
            guard isPro else { return }
            commitIfEntitled(previewAccent, customHex: customColor.accentHexValue)
            #if os(iOS)
            if let previewIcon { applyIcon(previewIcon) }
            #endif
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionSheet(subscriptionPresented: $showPaywall)
        }
        #if os(iOS)
        .alert("Couldn't change the icon", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(iconError ?? "")
        }
        #endif
    }

    // MARK: - Preview

    private var previewColor: Color {
        switch previewAccent {
        case .systemBlue: return .accentColor
        case .custom:     return customColor
        case .team:       return store.teamHex.map(Color.init(accentHex:)) ?? .accentColor
        default:          return previewAccent.swatch
        }
    }

    private var previewSection: some View {
        Section {
            ThemePreviewCard(accent: previewColor)
                .tint(previewColor)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Accent

    private var accentSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 14) {
                ForEach(AppAccent.curated) { accent in
                    AccentSwatch(
                        color: accent.swatch,
                        name: accent.displayName,
                        isSelected: previewAccent == accent
                    ) {
                        select(accent)
                    }
                }
            }
            .padding(.vertical, 6)

            teamRow

            ColorPicker(selection: $customColor, supportsOpacity: false) {
                HStack {
                    Label("Custom Color", systemImage: "paintpalette")
                    if previewAccent == .custom {
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(previewColor)
                    }
                }
            }
        } header: {
            Text("Accent Color")
        } footer: {
            Text("Tints buttons, highlights and selections across the app, widgets and Live Activities. Sport, team and live colors stay as they are.")
        }
    }

    @ViewBuilder
    private var teamRow: some View {
        if teamCandidates.isEmpty {
            HStack {
                Label("Team Colors", systemImage: "tshirt")
                Spacer()
                Text("Follow a team to use its color")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Button {
                    if store.teamID == nil, let first = teamCandidates.first {
                        store.setTeam(id: first.id, name: first.name, hex: first.hex)
                    }
                    select(.team)
                } label: {
                    HStack {
                        Circle()
                            .fill(store.teamHex.map(Color.init(accentHex:)) ?? teamCandidates[0].color)
                            .frame(width: 22, height: 22)
                        Text("Team Colors")
                        if previewAccent == .team {
                            Image(systemName: "checkmark")
                                .foregroundStyle(previewColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if teamCandidates.count > 1 {
                    Picker("Team", selection: Binding(
                        get: { store.teamID ?? teamCandidates[0].id },
                        set: { id in
                            guard let team = teamCandidates.first(where: { $0.id == id }) else { return }
                            store.setTeam(id: team.id, name: team.name, hex: team.hex)
                            select(.team)
                        }
                    )) {
                        ForEach(teamCandidates) { team in
                            Text(team.name).tag(team.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(teamCandidates[0].name)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func select(_ accent: AppAccent) {
        withAnimation(.snappy) { previewAccent = accent }
        commitIfEntitled(accent, customHex: customColor.accentHexValue)
    }

    /// Pro users apply on tap; free users only preview.
    private func commitIfEntitled(_ accent: AppAccent, customHex: Int) {
        guard isEntitled else { return }
        if accent == .custom { store.customHex = customHex }
        store.accent = accent
    }

    // MARK: - App icon (iOS)

    #if os(iOS)
    private var iconSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
                ForEach(AppIconChoice.allCases) { icon in
                    Button {
                        tapIcon(icon)
                    } label: {
                        VStack(spacing: 6) {
                            AppIconThumbnail(icon: icon)
                                .frame(width: 60, height: 60)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(highlightedIcon == icon ? previewColor : .clear, lineWidth: 3)
                                        .padding(-4)
                                }
                            Text(icon.displayName)
                                .font(.caption)
                                .foregroundStyle(highlightedIcon == icon ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(icon.displayName) icon")
                    .accessibilityAddTraits(highlightedIcon == icon ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("App Icon")
        }
    }

    private var highlightedIcon: AppIconChoice { previewIcon ?? currentIcon }

    private func tapIcon(_ icon: AppIconChoice) {
        guard isEntitled || icon == .standard else {
            previewIcon = icon
            requestPro()
            return
        }
        previewIcon = nil
        applyIcon(icon)
    }

    private func applyIcon(_ icon: AppIconChoice) {
        Task {
            do {
                try await AppIconChoice.apply(icon)
                currentIcon = AppIconChoice.current
                previewIcon = nil
            } catch {
                iconError = error.localizedDescription
            }
        }
    }
    #endif

    // MARK: - Unlock

    private var unlockSection: some View {
        Section {
            Button {
                requestPro()
            } label: {
                Label(
                    previewAccent == .systemBlue ? "Unlock Themes with Pro" : "Apply with Scoreline Pro",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(previewColor)
            .listRowBackground(Color.clear)
        } footer: {
            Text(ProFeature.themes.blurb + " Preview anything here; applying it needs Scoreline Pro.")
        }
    }

    private func requestPro() {
        MonetizationTelemetry.gateHit(.themes)
        UpsellCoordinator.shared.requestExplicit(.theme) {
            showPaywall = true
        }
    }
}

// MARK: - Team colors

/// A followed team with a known color (teams carry no color; games do).
struct TeamAccentCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let hex: Int

    var color: Color { Color(accentHex: hex) }

    static func collect(favoriteIDs: Set<String>, games: [Game]) -> [TeamAccentCandidate] {
        guard !favoriteIDs.isEmpty else { return [] }
        var found: [String: TeamAccentCandidate] = [:]
        for game in games {
            for (id, name, color) in [
                (game.idHomeTeam, game.strHomeTeam, game.homeTeamColor),
                (game.idAwayTeam, game.strAwayTeam, game.awayTeamColor),
            ] {
                guard let id, favoriteIDs.contains(id), found[id] == nil,
                      let hex = parseHex(color) else { continue }
                found[id] = TeamAccentCandidate(id: id, name: name, hex: hex)
            }
            if found.count == favoriteIDs.count { break }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parseHex(_ string: String?) -> Int? {
        guard let string else { return nil }
        let clean = string.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6 else { return nil }
        return Int(clean, radix: 16)
    }
}

// MARK: - Components

private struct AccentSwatch: View {
    let color: Color
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(4)
                .overlay {
                    Circle().strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(name)
    }
}

/// A miniature of a typical screen, tinted with the previewed accent.
private struct ThemePreviewCard: View {
    let accent: Color
    @State private var alertsOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["Today", "Tomorrow", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.subheadline.weight(day == "Today" ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(day == "Today" ? accent : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(day == "Today" ? Color.white : Color.primary)
                }
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lakers at Celtics")
                        .font(.headline)
                    Text("7:30 PM · TD Garden")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "bell.fill")
                    .foregroundStyle(.tint)
            }
            Toggle("Score alerts", isOn: $alertsOn)
            HStack {
                Button("Follow") { }
                    .buttonStyle(.borderedProminent)
                Button("Team Page") { }
                    .buttonStyle(.bordered)
                Spacer()
                Text("See all")
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// A drawn stand-in for an app icon variant: the calendar body, header bar and
/// a grid of game dots, in the variant's colors.
struct AppIconThumbnail: View {
    let icon: AppIconChoice

    var body: some View {
        let colors = icon.thumbnailColors
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let dot = side * 0.1
            ZStack(alignment: .top) {
                Color(accentHex: colors.body)
                Color(accentHex: colors.header)
                    .frame(height: side * 0.21)
                VStack(spacing: side * 0.05) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: side * 0.07) {
                            ForEach(0..<5, id: \.self) { col in
                                Circle()
                                    .fill(Self.dotColor(row: row, col: col))
                                    .frame(width: dot, height: dot)
                            }
                        }
                    }
                }
                .padding(.top, side * 0.3)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func dotColor(row: Int, col: Int) -> Color {
        switch (row, col) {
        case (0, 0), (0, 3), (1, 2), (3, 3): return Color(accentHex: 0xCC4100)
        case (2, 1), (3, 2): return Color(accentHex: 0x0033FF)
        case (0, 2), (1, 1), (2, 3): return .white
        case (1, 3): return Color(accentHex: 0x2C2222)
        default: return Color(accentHex: 0xD8D8D8)
        }
    }
}

// MARK: - Color → hex

extension Color {
    /// 0xRRGGBB of this color resolved in sRGB, clamped (ColorPicker can hand back
    /// extended-range values).
    var accentHexValue: Int {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ value: Float) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return (byte(resolved.red) << 16) | (byte(resolved.green) << 8) | byte(resolved.blue)
    }
}

#Preview("Themes") {
    NavigationStack {
        ThemeSettingsView()
    }
    .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
    .environment(Favorites())
}

#Preview("Icon thumbnails") {
    HStack(spacing: 12) {
        ForEach(AppIconChoice.allCases) { icon in
            AppIconThumbnail(icon: icon)
                .frame(width: 56, height: 56)
        }
    }
    .padding()
}
