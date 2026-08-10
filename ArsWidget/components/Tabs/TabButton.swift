//
//  TabButton.swift
//  ArsWidget
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .frame(minWidth: 38, minHeight: 26)
                // The whole tab cell is clickable, not just the drawn pixels
                // of the SF Symbol. This matters for the Games button beside
                // the notch edge.
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) { }
}
