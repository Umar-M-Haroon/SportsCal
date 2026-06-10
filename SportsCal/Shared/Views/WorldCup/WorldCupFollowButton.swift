//
//  WorldCupFollowButton.swift
//  SportsCal
//
//  One-tap "Follow World Cup": subscribes the user to notifications for every
//  upcoming World Cup match. Backed by `followWorldCup`; GameViewModel reconciles the
//  concrete event IDs into autoFollow each fetch (and as the bracket fills in).
//

import SwiftUI
import SportsCalModel

struct WorldCupFollowButton: View {
    @Environment(GameViewModel.self) private var viewModel
    @AppStorage("followWorldCup") private var followWorldCup: Bool = false

    var body: some View {
        Button {
            followWorldCup.toggle()
            if followWorldCup {
                #if os(iOS)
                viewModel.reconcileWorldCupFollows()
                #endif
            }
        } label: {
            Label(
                followWorldCup ? "Following World Cup" : "Follow World Cup",
                systemImage: followWorldCup ? "bell.fill" : "bell"
            )
            .font(.appHeadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .appSpace2)
        }
        .buttonStyle(.borderedProminent)
        .tint(.app(.soccer))
    }
}
