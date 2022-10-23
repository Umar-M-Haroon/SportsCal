//
//  CompetitionView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/4/22.
//

import SwiftUI

struct CompetitionView: View {
    var competition: String
    @Binding var isHidden: Bool
    var body: some View {
        HStack {
            Toggle(isOn: $isHidden) {
                Text(competition)
            }
        }
    }
}

struct CompetitionView_Previews: PreviewProvider {
    static var previews: some View {
        CompetitionView(competition: "Serie A", isHidden: Binding<Bool>.constant(false))
    }
}
