import SwiftUI
import MuralCore

/// The phrases Mural just used, offered for keeping.
///
/// One full-width row each, stacked. Side by side they had to share a phone's width, which
/// truncated the middle of every phrase once Mural offered more than one — and a phrase you
/// cannot read is a phrase you cannot decide about. Stacked, each one wraps and is read whole.
struct PhraseChips: View {
    let coordinator: ConversationCoordinator
    private var phrases: [String] { coordinator.capturablePhrases }
    private static let shape = RoundedRectangle(cornerRadius: 18)

    var body: some View {
        if !phrases.isEmpty {
            VStack(spacing: 8) {
                ForEach(phrases, id: \.self) { phrase in
                    chip(phrase)
                }
                if phrases.count > 1 { saveAll }
            }
            // No identifier on the stack: an accessibility modifier on a bare VStack collapses
            // it into one element and the rows stop being offered as separate buttons.
            .padding(.vertical, 3)
        }
    }

    private func chip(_ phrase: String) -> some View {
        let saved = coordinator.isPhraseSaved(phrase)
        return Button { coordinator.savePhrases([phrase]) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: saved ? "checkmark" : "plus").font(.caption2)
                Text(phrase).font(.system(.subheadline, design: .rounded))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(saved ? MuralColor.sage : MuralColor.butter, in: Self.shape)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .accessibilityLabel(saved ? "\(phrase), already saved" : "Save \(phrase)")
        .accessibilityIdentifier("phrase-chip")
    }

    private var saveAll: some View {
        let unsaved = phrases.filter { !coordinator.isPhraseSaved($0) }
        return Button { coordinator.savePhrases(phrases) } label: {
            HStack(spacing: 9) {
                Image(systemName: "tray.and.arrow.down").font(.caption2)
                Text("Save all").font(.system(.subheadline, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.peach, in: Self.shape)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .disabled(unsaved.isEmpty)
        .accessibilityLabel("Save all \(phrases.count) phrases")
        .accessibilityIdentifier("phrase-save-all")
    }
}

/// Kept phrases: the target language first, its meaning underneath.
///
/// This is a tab of its own rather than something to find at the bottom of Words. The two lists
/// are different in kind — a recall bar is earned in conversation and a kept phrase is only a
/// bookmark — and giving each its own place says so without a sentence of explanation.
struct PhrasesView: View {
    let coordinator: ConversationCoordinator
    @State private var deleting: SavedPhrase?
    @State private var search = ""
    private var phrases: [SavedPhrase] { coordinator.store.savedPhrases }
    private var found: [SavedPhrase] { phrases.filter { $0.matches(search) } }

    var body: some View {
        Group {
            if phrases.isEmpty { empty } else { list }
        }
        .background(MuralColor.cream).foregroundStyle(MuralColor.ink)
        .confirmationDialog("Remove this phrase?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove phrase", role: .destructive) {
                if let deleting { coordinator.store.deletePhrase(deleting.id) }
                deleting = nil
            }
        }
    }

    private var heading: some View {
        PageHeading(eyebrow: "Kept by you · \(coordinator.language.name)", title: "Your phrases.",
                    subtitle: "The lines you wanted to keep.")
    }

    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heading
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "bookmark").font(.system(size: 34, weight: .light))
                    Text("Nothing kept yet.").font(.system(.title2, design: .rounded, weight: .medium))
                    Text("When Mural uses a \(coordinator.language.name) phrase, tap it under the caption to keep it here with its meaning.")
                        .font(.subheadline).foregroundStyle(MuralColor.secondary)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MuralColor.sage, in: RoundedRectangle(cornerRadius: 28))
                    .accessibilityIdentifier("saved-phrases-empty")
            }.padding(26)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 14)
            phraseList
        }.searchable(text: $search, prompt: "Find a phrase")
    }

    private var phraseList: some View {
        List {
            if found.isEmpty {
                ContentUnavailableView.search(text: search).listRowBackground(MuralColor.cream)
                    .accessibilityIdentifier("saved-phrases-no-match")
            }
            ForEach(found) { phrase in
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
