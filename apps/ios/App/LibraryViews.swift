import SwiftUI
import UniformTypeIdentifiers
import MuralCore

struct ThemesView: View {
    let coordinator: ConversationCoordinator
    let choose: (ConversationTheme?) -> Void
    var openScans: () -> Void = {}
    @State private var search = ""
    @State private var category = "All"
    @State private var current = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var themes: [ConversationTheme] {
        coordinator.language.themes.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)) }
    }
    private var categories: [String] { coordinator.language.themes.map(\.category).reduce(into: ["All"]) { if !$0.contains($1) { $0.append($1) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "A place to begin", title: "What’s on\nyour mind?", subtitle: "Same friend. Somewhere new.")
                Button { choose(nil) } label: {
                    HStack { Image(systemName: "waveform"); Text("Just talk"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).foregroundStyle(MuralColor.onAccent).background(MuralColor.accent, in: RoundedRectangle(cornerRadius: 26))
                }
                if let course = coordinator.language.course {
                    CourseCard(course: course, language: coordinator.language) { choose($0) }
                }
                PictureCard(open: openScans)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c) { category = c }.font(.caption).padding(.horizontal, 15).padding(.vertical, 11)
                                .background(category == c ? MuralColor.selected : MuralColor.surface, in: Capsule())
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150), spacing: 12)], spacing: 12) {
                    ForEach(themes) { theme in
                        Button { if theme.id == "today" { current = true } else { choose(theme) } } label: {
                            VStack(alignment: .leading, spacing: 28) {
                                Image(systemName: theme.symbol).font(.system(size: 28, weight: .regular)).foregroundStyle(MuralColor.ink)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(theme.title).font(.system(.headline, design: .rounded))
                                    Text(theme.subtitle).font(.caption).foregroundStyle(MuralColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(19)
                                .background(MuralColor.surface, in: RoundedRectangle(cornerRadius: 27))
                        }.buttonStyle(.plain)
                    }
                }
                if themes.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24)
        }.foregroundStyle(MuralColor.ink)
            .searchable(text: $search, prompt: "Find a conversation")
            .sheet(isPresented: $current) { CurrentTopicView(coordinator: coordinator) { choose(coordinator.selectedTheme) } }
    }
}

struct CurrentTopicView: View {
    let coordinator: ConversationCoordinator
    let selected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var brief: TopicBrief?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "The world today", title: "A fresh conversation.", subtitle: "What would you like to talk about?")
                    TextField(coordinator.language.topicPlaceholder, text: $query, axis: .vertical).padding(18).background(MuralColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    Button { find() } label: {
                        HStack { Text(loading ? "Finding something interesting…" : "Find a topic"); Spacer(); if loading { ProgressView().tint(MuralColor.onAccent) } else { Image(systemName: "sparkle.magnifyingglass") } }.padding(18).foregroundStyle(brief == nil ? MuralColor.onAccent : MuralColor.ink)
                            .background(brief == nil ? MuralColor.accent : MuralColor.surface, in: Capsule())
                    }.disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary) }
                    if let brief {
                        Text(.init(brief.text)).font(.body).textSelection(.enabled)
                        SourcesView(sources: brief.sources, date: brief.retrievedAt)
                        Button("Talk about this", systemImage: "waveform") { coordinator.discuss(brief); selected(); dismiss() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).foregroundStyle(MuralColor.onAccent).background(MuralColor.accent, in: Capsule())
                    }
                    Text("Search uses your OpenAI API account. Sources stay attached to the topic.").font(.footnote).foregroundStyle(MuralColor.secondary)
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func find() {
        loading = true; error = nil
        Task { do { brief = try await coordinator.currentTopic(query) } catch { self.error = error.localizedDescription }; loading = false }
    }
}

struct SourcesView: View {
    var sources: [SourceLink]
    var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources · \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(MuralColor.secondary)
            ForEach(sources) { source in if let url = source.safeURL { Link(destination: url) { Label(source.title, systemImage: "arrow.up.right").font(.subheadline) } } }
        }
    }
}

/// The topics Mural found for the conversation on the Talk screen, with their sources, so a
/// claim it makes about current events can be checked. The whole conversation is read in
/// Settings, under Past conversations.
struct TopicSourcesView: View {
    let topics: [TopicBrief]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(topics) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .navigationTitle("Sources").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SessionHistoryView: View {
    let store: LearningStore
    /// Usage-only records carry the cost of scans and tests, not a conversation.
    private var conversations: [SessionRecord] { store.learningSessions.filter { !$0.isUsageOnly } }
    @State private var selected: SessionRecord?
    @State private var deleting: SessionRecord?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty { Text("Your \(store.language.name) conversations will appear here.").foregroundStyle(MuralColor.secondary) }
                ForEach(conversations) { session in
                    Button { selected = session } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(MuralColor.secondary)
                        }.padding(.vertical, 8)
                    }.swipeActions { Button("Delete", role: .destructive) { deleting = session }.disabled(session.endedAt == nil) }
                }
            }.scrollContentBackground(.hidden).background(MuralColor.cream)
                .navigationTitle("Past conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(item: $selected) { session in EditableTranscriptView(sessionID: session.id, store: store) }
            .confirmationDialog("Delete this conversation and its learning evidence?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete conversation", role: .destructive) { if let deleting { store.deleteSession(deleting.id) }; deleting = nil }
            }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EditableTranscriptView: View {
    let sessionID: UUID
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var editedText = ""
    private var session: SessionRecord? { store.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(session?.passages ?? []) { passage in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(passage.speaker == .user ? "YOU" : "MURAL").font(.caption).tracking(1)
                                Spacer()
                                if passage.speaker == .user && session?.endedAt != nil {
                                    Button("Edit") { editedText = passage.text; editingID = passage.id }.font(.caption)
                                }
                            }.foregroundStyle(MuralColor.secondary)
                            Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                            if let id = session?.languageID, let module = LanguageRegistry.module(for: id) { ReadingHelp(text: passage.text, language: module) }
                        }
                    }
                    ForEach(session?.topics ?? []) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .navigationTitle("Our conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("What you said", text: $editedText, axis: .vertical).lineLimit(4...10).padding(18).background(MuralColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    Text("Correct a misheard phrase. Learning evidence from the old wording will be removed; the original remains in your backup history.").font(.footnote).foregroundStyle(MuralColor.secondary)
                    Spacer()
                }.padding(24).background(MuralColor.cream).navigationTitle("What you said").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingID = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { if let id = editingID { store.correctPassage(sessionID: sessionID, passageID: id, text: editedText) }; editingID = nil } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
}

struct SettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = CredentialStore.hasKey
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: BackupDocument?
    @State private var deleting = false
    @State private var notices = false
    @State private var showingAPIKey = false
    @State private var sessions = false
    private var store: LearningStore { coordinator.store }
    private var totalVoiceSeconds: Double { store.sessions.reduce(0) { $0 + $1.voiceSeconds } }
    private var totalVoiceCost: Double { store.sessions.reduce(0) { $0 + $1.estimatedVoiceCost } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LearningLanguagePicker(coordinator: coordinator)
                    GuidanceLevelPicker(coordinator: coordinator)
                    Picker("Speaking pace", selection: Binding(get: { store.preferences.pace }, set: { coordinator.selectSpeechPace($0) })) {
                        ForEach(SpeechPace.allCases) { pace in Text(pace.title).tag(pace) }
                    }.pickerStyle(.menu).accessibilityIdentifier("speech-pace-picker")
                    Toggle("Meaning subtitles", isOn: Binding(get: { store.preferences.meaningVisible }, set: { value in
                        if value != store.preferences.meaningVisible { coordinator.toggleMeaning() }
                    }))
                    Picker("Meaning language", selection: Binding(get: { store.preferences.meaningLanguage }, set: { coordinator.selectMeaningLanguage($0) })) {
                        ForEach(MeaningLanguages.all, id: \.self) { Text($0) }
                    }
                    LabeledContent("Corrections", value: "Gently, as we talk")
                    TextField("A few things you enjoy", text: Binding(get: { store.preferences.interests }, set: { value in store.updatePreferences { $0.interests = String(value.prefix(500)) } }), axis: .vertical)
                } header: { Text("Just your pace") } footer: {
                    Text((coordinator.isRunning ? "End this conversation to switch languages. Each language keeps its own words and progress." : "Each language keeps its own words and progress. Mural finds your pace through conversation.")
                         + " Your level and speaking pace apply straight away. The pace is a request to Mural, not a change to the voice's speed, so how closely it is followed can vary.")
                }
                if ManagedAccountConfiguration.load() != nil {
                    Section {
                        NavigationLink { ManagedAccountView() } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }.disabled(coordinator.isRunning).accessibilityIdentifier("managed-account-settings")
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $showingAPIKey) {
                        if hasKey { Label("Your key is saved on this iPhone", systemImage: "checkmark.shield") }
                        SecureField(hasKey ? "Replace OpenAI key" : "OpenAI API key", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("api-key")
                        Button(hasKey ? "Save replacement key" : "Save key") {
                            do { try CredentialStore.save(key); key = ""; hasKey = true; message = "Saved securely. Start a conversation to connect." }
                            catch { message = error.localizedDescription }
                        }.disabled(key.isEmpty || coordinator.isRunning)
                        Link("Open OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        if hasKey {
                            Button("Remove key", role: .destructive) {
                                do { try CredentialStore.delete(); hasKey = false; message = "Your key has been removed." }
                                catch { message = error.localizedDescription }
                            }.disabled(coordinator.isRunning)
                        }
                        Text("Your OpenAI account pays for usage. The key stays in this iPhone’s Keychain and is sent only to OpenAI.")
                            .font(.footnote).foregroundStyle(MuralColor.secondary)
                    } label: { Label("Use your own API key", systemImage: "key").accessibilityIdentifier("advanced-api-key") }
                    if let message { Text(message).font(.footnote).foregroundStyle(MuralColor.secondary) }
                } header: { Text("Advanced") } footer: {
                    if !hasKey { Text("This version uses your OpenAI API key to start a conversation.") }
                }
                Section {
                    Picker("Conversation limit", selection: Binding(get: { store.preferences.sessionMinutes }, set: { value in store.updatePreferences { $0.sessionMinutes = value } })) {
                        ForEach([5, 10, 15, 20, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    NavigationLink { SpendingView(coordinator: coordinator) } label: {
                        Label("Spending by model", systemImage: "chart.bar.xaxis")
                    }.accessibilityIdentifier("spending-link")
                    LabeledContent("Voice time, all conversations", value: "\(Int(totalVoiceSeconds / 60)) min \(Int(totalVoiceSeconds) % 60) sec")
                    LabeledContent("Voice estimate, all conversations", value: String(format: "$%.2f USD", totalVoiceCost))
                    LabeledContent("Search calls recorded", value: "\(store.sessions.reduce(0) { $0 + $1.searchCalls })")
                    Link("OpenAI usage and billing", destination: URL(string: "https://platform.openai.com/usage")!)
                } header: { Text("Keep it comfortable") } footer: {
                    Text("Spending by model shows each month, and the real bill with an Admin key. Voice estimate uses $0.05 per open minute for GPT-Live 1, as of \(VoicePricing.asOf). Translation, teaching and search cost extra. Interrupted requests can be billed without a usage record here. Your OpenAI dashboard is authoritative. The time limit is local, not a billing cap.")
                }
                Section {
                    Button("Past conversations", systemImage: "clock.arrow.circlepath") { sessions = true }
                    Button("Export learning backup", systemImage: "square.and.arrow.up") {
                        do { backup = BackupDocument(data: try store.exportData()); exporting = true } catch { message = error.localizedDescription }
                    }
                    Button("Import learning backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(coordinator.isRunning)
                    Button("Delete all conversations and learning", role: .destructive) { deleting = true }.disabled(coordinator.isRunning)
                } header: { Text("Your words belong to you") } footer: {
                    Text("Backups include transcripts and learning evidence, never your API key. Import adds conversations with new IDs. Existing conversations stay unchanged. There is no cloud sync.")
                }
                Section {
                    Link("Privacy policy", destination: URL(string: "https://mural.chat/privacy/")!)
                        .accessibilityIdentifier("settings-privacy-policy")
                    Link("Terms of use", destination: URL(string: "https://mural.chat/terms/")!)
                        .accessibilityIdentifier("settings-terms")
                    Link("Contact support", destination: URL(string: "https://mural.chat/support/")!)
                        .accessibilityIdentifier("settings-support")
                } header: { Text("Help and privacy") }
                Section {
                    Text("Mural 0.1 · Personal build").font(.footnote)
                    Text("Voice: GPT-Live-1 · Teacher: GPT-5.6 Luna").font(.footnote)
                    Link("OpenAI data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                    Text("Audio and selected text go to OpenAI while you practise. Requests disable provider storage where supported; abuse-monitoring retention may still apply. Raw audio is not saved by Mural.").font(.footnote)
                    Button("Open-source notices") { notices = true }
                }
            }.scrollContentBackground(.hidden).background(MuralColor.cream).tint(MuralColor.secondary)
                .navigationTitle("Make yourself comfortable").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { key = ""; dismiss() } } }
        }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Mural-learning-backup") { result in if case .failure(let error) = result { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Archive.readImportData(from: url)); message = "Your backup has been imported."
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Delete all learning data on this phone?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete all learning data", role: .destructive) { coordinator.deleteLearningData() }
        } message: { Text("This removes conversations, vocabulary, saved phrases, scans and progress. Export a backup first if you want to keep them. Your API key and preferences remain.") }
        .sheet(isPresented: $sessions) { SessionHistoryView(store: store) }
        .sheet(isPresented: $notices) {
            NavigationStack {
                ScrollView { Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Notices unavailable.").font(.footnote).padding(24).textSelection(.enabled) }
                    .navigationTitle("Open-source notices").navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

struct GuidanceLevelPicker: View {
    let coordinator: ConversationCoordinator
    private var level: GuidanceLevel { coordinator.store.preferences.guidanceLevel }
    var body: some View {
        Picker("Your level", selection: Binding(get: { level }, set: { coordinator.selectGuidanceLevel($0) })) {
            ForEach(GuidanceLevel.allCases) { level in Text(level.title).tag(level) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("guidance-level-picker")
        Text(level.detail(language: coordinator.language, meaningLanguage: coordinator.store.preferences.meaningLanguage))
            .font(.footnote).foregroundStyle(MuralColor.secondary)
            .accessibilityIdentifier("guidance-level-detail")
    }
}

struct LearningLanguagePicker: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        Picker("Learning language", selection: Binding(get: { coordinator.language.id }, set: { coordinator.selectLanguage($0) })) {
            ForEach(LanguageRegistry.all) { language in Text(language.settingsTitle).tag(language.id) }
        }
        .pickerStyle(.menu)
        .disabled(coordinator.isRunning)
        .accessibilityIdentifier("learning-language-picker")
    }
}
