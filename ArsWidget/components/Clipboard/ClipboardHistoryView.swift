//
//  ClipboardHistoryView.swift
//  ArsWidget
//
//  Added in personal fork: notch tab showing recent clipboard text, click
//  any row to copy it back to the clipboard.
//

import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var clipboard = ClipboardManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: $clipboard.isEnabled) {
                    Text("История копирования")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()
                if !clipboard.history.isEmpty {
                    Button("Очистить") {
                        clipboard.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }

            if !clipboard.isEnabled {
                Text("Выключено — ничего не отслеживается")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if clipboard.history.isEmpty {
                        Text("Пока ничего не скопировано")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.top, 4)
                    } else {
                        ForEach(clipboard.history) { item in
                            ClipboardRow(item: item)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(.horizontal, 8)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    @ObservedObject var clipboard = ClipboardManager.shared
    @State private var justCopied = false

    var body: some View {
        Button {
            clipboard.copyToClipboard(item)
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                justCopied = false
            }
        } label: {
            HStack {
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if justCopied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ClipboardHistoryView()
        .frame(width: 300, height: 160)
        .background(.black)
}
