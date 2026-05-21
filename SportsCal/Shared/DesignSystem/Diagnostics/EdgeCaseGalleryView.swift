//
//  EdgeCaseGalleryView.swift
//  SportsCal — Diagnostics (Phase F)
//
//  Visual catalog of every empty-state preset + edge-case primitive in
//  the design system. Lets you eyeball them without having to engineer
//  the real conditions that would surface them.
//
//  Settings → Developer → "Edge case gallery"
//

import SwiftUI
import SportsCalModel

struct EdgeCaseGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace5) {
                section("Phase E · 12 wireframed empty states") {
                    galleryEntry("1. First launch") {
                        EmptyStateView.firstLaunch(onPickFavorites: {})
                    }
                    galleryEntry("2. Quiet day") {
                        EmptyStateView.quietDay(tomorrowCount: 4, onPeekTomorrow: {})
                    }
                    galleryEntry("3. No favorites") {
                        EmptyStateView.noFavorites(onPickFavorites: {})
                    }
                    galleryEntry("4. Favorites idle") {
                        EmptyStateView.favoritesIdle(otherGameCount: 9, onShowAll: {})
                    }
                    galleryEntry("5. All pre-game") {
                        EmptyStateView.allPreGame(firstKickoff: "7:30 PM ET")
                    }
                    galleryEntry("6. All final") {
                        EmptyStateView.allFinal(count: 7)
                    }
                    galleryEntry("8. Off-season · MLB") {
                        EmptyStateView.offSeason(.mlb, returnsIn: "47 days")
                    }
                    galleryEntry("9. Postponed") {
                        EmptyStateView.postponed(matchup: "NYY vs LAD", reason: "Rain delay — postponed to tomorrow.")
                    }
                    galleryEntry("10. Connection lost") {
                        EmptyStateView.connectionLost(onRetry: {})
                    }
                    galleryEntry("11. Loading skeleton (×3)") {
                        VStack(spacing: .appSpace2) {
                            SkeletonRow(); SkeletonRow(); SkeletonRow()
                        }
                    }
                    galleryEntry("12. Tip-off pill") {
                        HStack { TipoffPill(); Spacer() }
                            .padding(.appSpace4)
                    }
                }

                section("Phase F · Production edge primitives") {
                    galleryEntry("PaywallGate") {
                        PaywallGate(
                            feature: "Live Activities",
                            blurb: "Surface scores on your Lock Screen and Dynamic Island while a game is in progress.",
                            unlockAction: {}
                        )
                    }
                    galleryEntry("PermissionRequestCard · Notifications") {
                        PermissionRequestCard(permission: .notifications, action: {})
                    }
                    galleryEntry("PermissionRequestCard · Calendar") {
                        PermissionRequestCard(permission: .calendar, action: {})
                    }
                    galleryEntry("PermissionRequestCard · Live Activity") {
                        PermissionRequestCard(permission: .liveActivity, action: {})
                    }
                    galleryEntry("DegradedSectionPlaceholder") {
                        DegradedSectionPlaceholder(
                            symbol: "list.bullet.rectangle.portrait",
                            message: "Standings not available for this league.",
                            detail: "We'll add coverage as soon as the data feed includes it."
                        )
                    }
                    galleryEntry("StaleDataBanner") {
                        StaleDataBanner(lastUpdatedAgo: "4m ago", retryAction: {})
                            .padding(.appSpace3)
                    }
                }

                section("Production extras (cataloged in EmptyStatePresets)") {
                    galleryEntry("Search empty") {
                        EmptyStateView.searchEmpty(query: "verstapen")
                    }
                    galleryEntry("Filter empty") {
                        EmptyStateView.filterEmpty(disabledSports: [.basketball, .nfl], onReenable: {})
                    }
                    galleryEntry("Suspended in-progress") {
                        EmptyStateView.suspendedInProgress(matchup: "MIA vs MIL", sinceLabel: "9:42 PM")
                    }
                    galleryEntry("API error") {
                        EmptyStateView.apiError(onRetry: {})
                    }
                    galleryEntry("Watch reachability lost") {
                        EmptyStateView.watchReachabilityLost()
                    }
                }

                section("Component primitives sample") {
                    galleryEntry("LiveGameRow") {
                        LiveGameRow(
                            sport: .basketball,
                            matchup: "BOS vs LAL",
                            scoreLine: "112 — 106",
                            period: "Q4",
                            clock: "4:22",
                            subtext: "Tatum 38 · Davis 14R",
                            leverageLabel: "CLOSE",
                            leverageDelta: 6
                        )
                    }
                    galleryEntry("PreGameRow") {
                        PreGameRow(
                            sport: .soccer,
                            matchup: "JUV vs NAP",
                            kickoffLabel: "8:45 PM CET",
                            countdown: "in 1h 14m",
                            contextLine: "Serie A · matchday 32"
                        )
                    }
                    galleryEntry("FinalGameRow") {
                        FinalGameRow(
                            sport: .nfl,
                            homeAbbr: "PHI",
                            awayAbbr: "DAL",
                            homeScore: 28,
                            awayScore: 24
                        )
                    }
                    galleryEntry("CompactGameTile · live") {
                        CompactGameTile(
                            sport: .hockey,
                            state: .live,
                            shortStatus: "2P · 12:08",
                            matchup: "TOR · BOS",
                            scoreLine: "2 — 3"
                        )
                        .padding(.appSpace3)
                    }
                    galleryEntry("LiveTag · LeverageTag · SportChip") {
                        VStack(alignment: .leading, spacing: .appSpace2) {
                            HStack { LiveTag(period: "Q4", clock: "4:22"); Spacer() }
                            HStack { LeverageTag(label: "PLAYOFF G7", delta: 8); Spacer() }
                            HStack {
                                SportChip(sport: .basketball, selected: true)
                                SportChip(sport: .soccer)
                                SportChip(sport: .racing)
                                Spacer()
                            }
                        }
                        .padding(.appSpace3)
                    }
                }
            }
            .padding(.vertical, .appSpace4)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            Text(title)
                .appEyebrow()
                .padding(.horizontal, .appSpace4)
            content()
        }
    }

    private func galleryEntry<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appCaption)
                .foregroundStyle(Color.appInkFaint)
                .padding(.horizontal, .appSpace4)
            content()
                .padding(.horizontal, .appSpace4)
        }
    }
}
