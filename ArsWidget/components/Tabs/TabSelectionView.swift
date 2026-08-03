//
//  TabSelectionView.swift
//  ArsWidget
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Музыка", icon: "music.note", view: .home),
    TabModel(label: "Слова", icon: "textformat.abc", view: .vocab),
    TabModel(label: "Reminders", icon: "checklist", view: .reminders),
    TabModel(label: "Pomodoro", icon: "timer", view: .pomodoro),
    TabModel(label: "Игры", icon: "gamecontroller.fill", view: .games),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Система", icon: "gauge", view: .systemStats)
]

let leadingTabs = Array(tabs.prefix((tabs.count + 1) / 2))
let trailingTabs = Array(tabs.suffix(tabs.count / 2))

struct TabSelectionView: View {
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @Namespace var animation
    let tabItems: [TabModel]

    init(tabItems: [TabModel] = tabs) {
        self.tabItems = tabItems
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabItems) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    ArsWidgetHeader().environmentObject(ArsWidgetViewModel())
}
