//
//  LiveActivityStatusView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 12/6/22.
//

import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

@available(iOS 16.1, *)
struct LiveActivityStatusView: View {
    @Binding var liveActivityStatus: LiveActivityStatus
    var body: some View {
        Group {
            switch liveActivityStatus {
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
<<<<<<< HEAD
            case .added, .none:
=======
            case .added:
#if canImport(ActivityKit)
                if !Activity<LiveSportActivityAttributes>.activities.filter({$0.pushToken != nil}).isEmpty {
                    HStack {
                        Text("^[Following \(Activity<LiveSportActivityAttributes>.activities.filter({$0.pushToken != nil}).count) games](inflect: true)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button {
                            for activity in Activity<LiveSportActivityAttributes>.activities {
                                let currentState = activity.contentState
                                Task {
                                    await activity.end(using: currentState, dismissalPolicy: .immediate)
                                }
                            }
                            withAnimation {
                                if Activity<LiveSportActivityAttributes>.activities.isEmpty {
                                    liveActivityStatus = .none
                                }
                            }
                        } label: {
                            Text("End Activities")
                                .font(.caption2)
                        }
                    }
                }
#endif
            case .none:
>>>>>>> update live activities to work again
                EmptyView()
            }
        }
    }
}

@available(iOS 16.1, *)
struct LiveActivityStatus_Previews: PreviewProvider {
    static var previews: some View {
        LiveActivityStatusView(liveActivityStatus: .constant(.loading) )
    }
}
