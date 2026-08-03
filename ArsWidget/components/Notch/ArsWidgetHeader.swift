//
//  ArsWidgetHeader.swift
//  ArsWidget
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct ArsWidgetHeader: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    private var shouldShowTabs: Bool {
        ((!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.shelfEnabled]) || vm.notchState == .open
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if shouldShowTabs {
                    TabSelectionView(tabItems: leadingTabs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 8) {
                if vm.notchState == .open {
                    if shouldShowTabs {
                        TabSelectionView(tabItems: trailingTabs)
                    }

                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .allowsHitTesting(!coordinator.isFirstRunTourPresented)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    ArsWidgetHeader().environmentObject(ArsWidgetViewModel())
}
