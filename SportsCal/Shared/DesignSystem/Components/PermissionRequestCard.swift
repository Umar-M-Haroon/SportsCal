//
//  PermissionRequestCard.swift
//  SportsCal — Design System v1.0 (edge-case primitive #2 of 4)
//
//  Inline permission-request prompt for Notifications, Calendar, and
//  Live Activities. Same shape across permission types — symbol +
//  headline + reason + Allow button.
//

import SwiftUI

public struct PermissionRequestCard: View {
    public enum Permission {
        case notifications
        case calendar
        case liveActivity

        var symbol: String {
            switch self {
            case .notifications: return "bell.badge"
            case .calendar:      return "calendar.badge.plus"
            case .liveActivity:  return "dot.radiowaves.left.and.right"
            }
        }
        var title: String {
            switch self {
            case .notifications: return "Stay on top of game time"
            case .calendar:      return "Add games to your calendar"
            case .liveActivity:  return "Watch live in your Dynamic Island"
            }
        }
        var defaultBody: String {
            switch self {
            case .notifications: return "Allow notifications to get a ping when your favorites tip off, score, or finish."
            case .calendar:      return "We can drop a calendar event for any upcoming game so it lives next to the rest of your day."
            case .liveActivity:  return "Live Activities surface scores on your Lock Screen and Dynamic Island while a game is in progress."
            }
        }
        var ctaLabel: String {
            switch self {
            case .notifications: return "Allow notifications"
            case .calendar:      return "Allow calendar access"
            case .liveActivity:  return "Enable Live Activities"
            }
        }
    }

    public let permission: Permission
    public var bodyOverride: String? = nil
    public let action: () -> Void

    public init(
        permission: Permission,
        bodyOverride: String? = nil,
        action: @escaping () -> Void
    ) {
        self.permission = permission
        self.bodyOverride = bodyOverride
        self.action = action
    }

    public var body: some View {
        let bodyText = bodyOverride ?? permission.defaultBody
        VStack(spacing: .appSpace3) {
            HStack(spacing: .appSpace3) {
                Image(systemName: permission.symbol)
                    .font(.system(size: 28, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.appInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.title).font(.appHeadline)
                    Text(bodyText)
                        .font(.appCallout)
                        .foregroundStyle(Color.appInkSoft)
                }
            }
            Button(action: action) {
                Text(permission.ctaLabel)
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: .appHit)
            }
            .buttonStyle(.borderedProminent)
        }
        .appCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(permission.title). \(bodyText)"))
        .accessibilityAddTraits(.isButton)
    }
}
