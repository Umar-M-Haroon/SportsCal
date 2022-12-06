//
//  RemoveLiveActivityButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 12/5/22.
//

import SwiftUI

struct RemoveLiveActivityButton: View {
    var body: some View {
        Button(role: .destructive) {
            
        } label: {
            Text("Remove Live Activity")
                .font(.caption2)
        }
        .buttonStyle(.borderedProminent)

    }
}

struct RemoveLiveActivityButton_Previews: PreviewProvider {
    static var previews: some View {
        RemoveLiveActivityButton()
    }
}
