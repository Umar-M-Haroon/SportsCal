//
//  SportsCalControlWidget.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 2/15/26.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import AppIntents
import SportsCalModel

@available(iOS 18.0, *)
struct SportsCalControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SportsCalControl") {
            ControlWidgetButton(action: OpenSportsCalIntent()) {
                Label {
                    Text(controlText())
                } icon: {
                    Image(systemName: controlIcon())
                }
            }
        }
        .displayName("SportsCal")
        .description("See your next game at a glance")
    }

    private func controlText() -> String {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        return defaults?.string(forKey: "controlWidgetText") ?? "No upcoming games"
    }

    private func controlIcon() -> String {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        return defaults?.string(forKey: "controlWidgetIcon") ?? "sportscourt"
    }
}

@available(iOS 18.0, *)
struct OpenSportsCalIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open SportsCal"

    @Parameter(title: "Target")
    var target: OpenSportsCalTarget
}

@available(iOS 18.0, *)
struct OpenSportsCalTarget: AppEntity {
    let id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "SportsCal"
    static var defaultQuery = OpenSportsCalQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "SportsCal")
    }

    static var defaultValue: OpenSportsCalTarget {
        OpenSportsCalTarget(id: "default")
    }
}

@available(iOS 18.0, *)
struct OpenSportsCalQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [OpenSportsCalTarget] {
        identifiers.map { OpenSportsCalTarget(id: $0) }
    }

    func suggestedEntities() async throws -> [OpenSportsCalTarget] {
        [OpenSportsCalTarget(id: "default")]
    }

    func defaultResult() async -> OpenSportsCalTarget? {
        OpenSportsCalTarget(id: "default")
    }
}
#endif
