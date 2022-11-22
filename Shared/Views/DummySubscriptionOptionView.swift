//
//  DummySubscriptionOptionView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/6/22.
//

import SwiftUI
import SportsCalModel
struct DummySubscriptionOptionView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Includes 1 week trial!")
//                .font(.caption)
                .foregroundColor(.secondary)
            .font(.headline)
                Text("Save 20%!")
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                    .padding(4)
                    
        }

    }
}

struct DummySubscriptionOptionView_Previews: PreviewProvider {
    static var previews: some View {
        DummySubscriptionOptionView()
    }
}
