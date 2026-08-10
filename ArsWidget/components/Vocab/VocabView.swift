//
//  VocabView.swift
//  ArsWidget
//
//  Вкладка «Слова». Языки разложены по вкладкам: выбранная вкладка решает,
//  чей список слов виден, а галочка «учу этот язык» — кого спрашивать. Раньше
//  эти два разных смысла делили один ряд из кружков и выпадающего списка, и
//  понять, что за список перед тобой, было нельзя.
//
//  Сама карточка опроса — VocabPromptOverlayWindow.
//

import SwiftUI

struct VocabView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var vocab = VocabManager.shared
    @State private var showTopics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            languageTabs
            packControls
            Divider().overlay(Color.white.opacity(0.1))
            wordList
        }
        .padding(.horizontal, 8)
        .foregroundStyle(.white)
        .onAppear { vm.updateOpenSizeIfNeeded() }
    }

    // MARK: Шапка

    private var header: some View {
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
    }

    // MARK: Вкладки языков

    private var languageTabs: some View {
        HStack(spacing: 4) {
            ForEach(VocabLanguagePack.allCases) { pack in
                languageTab(pack)
            }
            Spacer(minLength: 0)
        }
    }

    private func languageTab(_ pack: VocabLanguagePack) -> some View {
        let isSelected = vocab.languagePack == pack
        let isLearning = vocab.isPackEnabled(pack)
        let color = VocabManager.color(for: pack)

        return Button {
            vocab.languagePack = pack
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .opacity(isLearning ? 1 : 0.35)
                    Text(vocab.title(for: pack))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.6))

                // Подчёркивание выбранной вкладки — тем же цветом языка.
                Rectangle()
                    .fill(isSelected ? color : .clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isLearning ? Text("Этот язык сейчас изучается") : Text("Язык открыт для просмотра, но не изучается"))
    }

    // MARK: Настройки выбранной вкладки

    private var packControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { vocab.isPackEnabled(vocab.languagePack) },
                    set: { vocab.setPackEnabled(vocab.languagePack, enabled: $0) }
                )) {
                    Text("Учу этот язык")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                directionChips

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Picker("Уровень", selection: Binding(
                    get: { vocab.selectedLevel(for: vocab.languagePack) },
                    set: { vocab.setSelectedLevel($0, for: vocab.languagePack) }
                )) {
                    ForEach(VocabLevel.allCases) { level in
                        Text("\(level.rawValue) — \(level.subtitle)").tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)

                Toggle("Пополнять автоматически", isOn: $vocab.autoFillEnabled)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("\(vocab.activeCount) из \(vocab.activeTarget) в очереди")
                Text("·")
                Text("в базе \(vocab.totalPackCount(for: vocab.languagePack))")
                if vocab.reviewCount(for: vocab.languagePack) > 0 {
                    Text("·")
                    Text("на повторении \(vocab.reviewCount(for: vocab.languagePack))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))

            HStack {
                Stepper("Очередь: \(vocab.activeTarget)", value: $vocab.activeTarget, in: 3...20)
                .font(.caption)

                Spacer()

                Stepper("Каждые \(vocab.intervalMinutes) мин", value: $vocab.intervalMinutes, in: 1...120)
                    .font(.caption)

                Picker("", selection: Binding(get: { vocab.direction }, set: { vocab.direction = $0 })) {
                    ForEach(VocabDirection.allCases) { direction in
                        Text(vocab.directionLabel(direction)).tag(direction)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.smooth) { showTopics.toggle() }
                } label: {
                    Label("Добавить слова", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))

                Button("Показать слово сейчас") {
                    vocab.showRandomWord()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(vocab.totalActiveCount == 0 ? 0.3 : 0.8))
                .disabled(vocab.totalActiveCount == 0)

                Spacer(minLength: 0)

                if vocab.deletedCount > 0 {
                    Button("Вернуть удалённые (\(vocab.deletedCount))") {
                        vocab.restoreDeletedWords()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }

            if showTopics {
                topicPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Пара языков цветом: слева то, что спрашивают, справа — чем отвечать.
    /// Подпись всегда есть, цвет только помогает узнать пару быстрее.
    private var directionChips: some View {
        let pack = vocab.languagePack
        let packColor = VocabManager.color(for: pack)
        let ruFirst = vocab.direction != .ukToRu

        return HStack(spacing: 5) {
            languageChip(ruFirst ? "Русский" : vocab.targetLabel(for: pack),
                         color: ruFirst ? VocabManager.sourceColor : packColor)
            Image(systemName: vocab.direction == .mixed ? "arrow.left.arrow.right" : "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
            languageChip(ruFirst ? vocab.targetLabel(for: pack) : "Русский",
                         color: ruFirst ? packColor : VocabManager.sourceColor)
        }
    }

    private func languageChip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    /// Уровни из большого словаря — то, чем словарь пополняется по-настоящему.
    /// Тем ниже остаются как быстрый способ взять слова одной темой.
    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("По уровню сложности")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            ForEach(VocabLevel.allCases) { level in
                let available = vocab.availableCount(level: level)
                HStack(spacing: 8) {
                    Text(level.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 24, alignment: .leading)
                    Text(level.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if available == 0 {
                        Text("всё добавлено")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        Text("осталось \(available)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                        Button("+20") { vocab.addWords(level: level, count: 20) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("+50") { vocab.addWords(level: level, count: 50) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !VocabManager.levelPack(for: vocab.languagePack).isEmpty {
                levelPicker
                Divider().overlay(Color.white.opacity(0.1))
                Text("Или готовой темой")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            let topics = VocabManager.topics(for: vocab.languagePack)
            if topics.isEmpty {
                Text("Для своего набора готовых тем нет — слова добавляются вручную в настройках.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Button {
                    SettingsWindowController.shared.showWindow(selecting: "Vocab")
                } label: {
                    Label("Открыть настройки словаря", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            } else {
                ForEach(topics) { topic in
                    let remaining = vocab.newWordCount(in: topic)
                    HStack(spacing: 8) {
                        Text(topic.title)
                            .font(.caption)
                        Spacer(minLength: 0)
                        if remaining == 0 {
                            Text("уже добавлено")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            Button("Добавить \(remaining)") {
                                vocab.addTopic(topic)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Button {
                    SettingsWindowController.shared.showWindow(selecting: "Vocab")
                } label: {
                    Label("Свои слова и языки", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Список слов

    private var wordList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if vocab.visibleWords.isEmpty {
                    Text("В этом наборе пока нет слов. Добавьте готовую тему выше.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 12)
                }
                ForEach(vocab.visibleWords) { word in
                    WordRow(word: word)
                }
            }
        }
        .frame(maxHeight: 320)
    }
}

private struct WordRow: View {
    let word: VocabWord
    @ObservedObject var vocab = VocabManager.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                vocab.setActive(word, active: !word.isActive)
            } label: {
                Image(systemName: word.isActive ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(word.isActive ? VocabManager.color(for: vocab.languagePack) : .white.opacity(0.4))
            .help(word.isActive ? Text("Убрать из изучения") : Text("Взять в изучение"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(word.ru)
                        .foregroundStyle(VocabManager.sourceColor.opacity(word.isActive ? 1 : 0.55))
                    Text("—")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(word.uk)
                        .foregroundStyle(VocabManager.color(for: vocab.languagePack).opacity(word.isActive ? 1 : 0.55))
                }
                .font(.system(size: 12))
                .lineLimit(1)

                if word.box >= 4 {
                    Text("Уже знаю")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }

            actionMenu

            // Удаление одним нажатием — то, ради чего раньше приходилось
            // открывать меню, и только для своих слов.
            Button {
                vocab.removeWord(word)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.8 : 0.3))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Удалить слово навсегда"))

            Spacer()

            progressDots
        }
        .onHover { isHovering = $0 }
    }

    private var progressDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < min(word.box, 4) ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
        .help(Text("Прогресс: \(min(word.box, 4)) из 4"))
    }

    private var actionMenu: some View {
        Menu {
            Button(word.isActive ? "Убрать из изучения" : "Изучать") {
                vocab.setActive(word, active: !word.isActive)
            }

            Button("Сбросить прогресс") {
                vocab.resetProgress(for: word)
            }

            if word.box < 4 {
                Button("Уже знаю") {
                    vocab.markMastered(word)
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
        .frame(width: 640, height: 470)
        .background(.black)
}
