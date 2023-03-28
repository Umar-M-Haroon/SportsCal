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
            case .added, .none:
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
