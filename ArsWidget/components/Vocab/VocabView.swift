//
//  VocabView.swift
//  ArsWidget
//
//  Added in personal fork: "Слова" tab — pick which Ukrainian words you're
//  studying, set how often they pop up and in which direction, and see
//  your progress. The actual quiz card is VocabPromptOverlayWindow.
//

import SwiftUI

struct VocabView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var vocab = VocabManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            Divider().overlay(Color.white.opacity(0.1))
            wordList
        }
        .padding(.horizontal, 8)
        .onAppear {
            vm.updateOpenSizeIfNeeded()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: $vocab.isEnabled) {
                    Text("Изучение языков")
                        .font(.system(size: 14, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Text("\(vocab.totalActiveCount) слов в изучении")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Text("\(vocab.sourceLanguageLabel) → \(vocab.targetLanguageLabel)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 6) {
                ForEach(VocabLanguagePack.allCases) { pack in
                    Button {
                        vocab.setPackEnabled(pack, enabled: !vocab.isPackEnabled(pack))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vocab.isPackEnabled(pack) ? "checkmark.circle.fill" : "circle")
                            Text(pack.targetCode)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(vocab.languagePack == pack ? 0.14 : 0.08)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(vocab.isPackEnabled(pack) ? .white : .white.opacity(0.45))
                }

                Spacer()

                Picker("", selection: Binding(get: { vocab.languagePack }, set: { vocab.languagePack = $0 })) {
                    ForEach(VocabLanguagePack.allCases) { pack in
                        Text(vocab.title(for: pack)).tag(pack)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            if vocab.isEnabled && vocab.totalActiveCount == 0 {
                Text("При включении автоматически появится стартовый набор слов.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack {
                Stepper(
                    "Каждые \(vocab.intervalMinutes) мин",
                    value: $vocab.intervalMinutes, in: 1...120, step: 1
                )
                .font(.caption)

                Spacer()

                Picker("", selection: Binding(get: { vocab.direction }, set: { vocab.direction = $0 })) {
                    ForEach(VocabDirection.allCases) { direction in
                        Text(vocab.directionLabel(direction)).tag(direction)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            Button("Показать слово сейчас") {
                vocab.showRandomWord()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(vocab.totalActiveCount == 0 ? 0.3 : 0.8))
            .disabled(vocab.totalActiveCount == 0)

            Button {
                SettingsWindowController.shared.showWindow(selecting: "Vocab")
            } label: {
                Label("Добавить язык или термины", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.82))
        }
        .foregroundStyle(.white)
    }

    private var wordList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(vocab.visibleWords) { word in
                    WordRow(word: word)
                }
            }
        }
        .frame(maxHeight: 360)
    }
}

private struct WordRow: View {
    let word: VocabWord
    @ObservedObject var vocab = VocabManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                vocab.setActive(word, active: !word.isActive)
            } label: {
                Image(systemName: word.isActive ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(word.isActive ? .cyan : .white.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(word.ru) — \(word.uk)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(word.isActive ? 1 : 0.6))
                        .lineLimit(1)

                    if word.isCustom {
                        Text("своё")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.cyan.opacity(0.85)))
                    }
                }

                if word.box >= 4 {
                    Text("Уже выучено")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }

            Spacer()

            progressDots

            actionMenu
        }
    }

    private var progressDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < min(word.box, 4) ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var actionMenu: some View {
        Menu {
            Button(word.isActive ? "Убрать из изучения" : "Изучать") {
                vocab.setActive(word, active: !word.isActive)
            }

            Button("Сбросить прогресс") {
                vocab.resetProgress(for: word)
            }

            Button("Уже знаю") {
                vocab.markMastered(word)
            }

            if word.isCustom {
                Divider()
                Button("Удалить слово", role: .destructive) {
                    vocab.removeWord(word)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.white.opacity(0.45))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    VocabView()
        .frame(width: 300, height: 220)
        .background(.black)
}
