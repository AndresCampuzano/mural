import SwiftUI
import MuralCore

/// The phrases Mural just used, offered for keeping.
///
/// A phone caption leaves very little room, so this is one horizontally scrolling row of
/// capsules rather than a list: each capsule shows its phrase on a single line, the whole row
/// costs one line of height whatever Mural said, and the kept phrases are read on their own
/// screen instead of here.
struct PhraseChips: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    private var phrases: [String] { coordinator.capturablePhrases }

    var body: some View {
        if !phrases.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(phrases, id: \.self) { phrase in
                        chip(phrase)
                    }
                    if phrases.count > 1 { saveAll }
                }.padding(.horizontal, 2).padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("phrase-chips")
        }
    }

    private func chip(_ phrase: String) -> some View {
        let saved = coordinator.isPhraseSaved(phrase)
        return Button { coordinator.savePhrases([phrase]) } label: {
            HStack(spacing: 6) {
                Image(systemName: saved ? "checkmark" : "plus").font(.caption2)
                Text(phrase).font(.system(.subheadline, design: .rounded))
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 190)
            .background(saved ? MuralColor.sage : MuralColor.butter, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityLabel(saved ? "\(phrase), already saved" : "Save \(phrase)")
        .accessibilityIdentifier("phrase-chip")
    }

    private var saveAll: some View {
        let unsaved = phrases.filter { !coordinator.isPhraseSaved($0) }
        return Button { coordinator.savePhrases(phrases) } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.caption2)
                Text("Save all").font(.system(.subheadline, design: .rounded))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(MuralColor.peach, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(unsaved.isEmpty)
        .accessibilityLabel("Save all \(phrases.count) phrases")
        .accessibilityIdentifier("phrase-save-all")
    }
}

/// Kept phrases: the target language first, its meaning underneath.
struct SavedPhrasesView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SavedPhrase?
    private var phrases: [SavedPhrase] { coordinator.store.savedPhrases }

    var body: some View {
        NavigationStack {
            Group {
                if phrases.isEmpty { empty } else { list }
            }
            .background(MuralColor.cream).foregroundStyle(MuralColor.ink)
            .navigationTitle("Saved phrases").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .confirmationDialog("Remove this phrase?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove phrase", role: .destructive) {
                if let deleting { coordinator.store.deletePhrase(deleting.id) }
                deleting = nil
            }
        }

    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bookmark").font(.system(size: 34, weight: .light))
            Text("Nothing kept yet.").font(.system(.title2, design: .rounded, weight: .medium))
            Text("When Mural uses a \(coordinator.language.name) phrase, tap it under the caption to keep it here with its meaning.")
                .font(.subheadline).foregroundStyle(MuralColor.secondary)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.sage, in: RoundedRectangle(cornerRadius: 28)).padding(26)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("saved-phrases-empty")
    }

    private var list: some View {
        List {
            ForEach(phrases) { phrase in
                VStack(alignment: .leading, spacing: 6) {
                    Text(phrase.text).font(.system(.title3, design: .rounded, weight: .medium))
                        .textSelection(.enabled).accessibilityIdentifier("saved-phrase-text")
                    if let module = LanguageRegistry.module(for: phrase.languageID) {
                        ReadingHelp(text: phrase.text, language: module)
                    }
                    Text(phrase.meaning.isEmpty ? (coordinator.phraseMeaningsLoading ? "Finding the meaning…" : "No meaning yet") : phrase.meaning)
                        .font(.subheadline).foregroundStyle(MuralColor.secondary)
                        .accessibilityIdentifier("saved-phrase-meaning")
                    Text(phrase.savedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(MuralColor.secondary)
                }.padding(.vertical, 8)
                    .listRowBackground(MuralColor.cream)
                    .swipeActions { Button("Remove", role: .destructive) { deleting = phrase } }
            }
            // Meanings are fetched only when asked for, so opening this list never spends
            // anything on its own.
            if phrases.contains(where: { $0.meaning.isEmpty }) {
                Button("Find the missing meanings", systemImage: "sparkles") { coordinator.refreshPhraseMeanings() }
                    .font(.subheadline).listRowBackground(MuralColor.cream)
                    .accessibilityIdentifier("saved-phrases-meanings")
            }
            Text("Saved phrases are a notebook, not a measure of recall. Keeping one here does not change your words or their bars.")
                .font(.footnote).foregroundStyle(MuralColor.secondary)
                .listRowBackground(MuralColor.cream)
        }.scrollContentBackground(.hidden)
    }
}
