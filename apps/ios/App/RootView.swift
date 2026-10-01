import SwiftUI
import MuralCore

struct RootView: View {
    @State private var coordinator: ConversationCoordinator
    @State private var tab = 0
    @State private var onboarding = false
    @Environment(\.scenePhase) private var scenePhase
    init(store: LearningStore) {
        let coordinator = ConversationCoordinator(store: store)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview"), ProcessInfo.processInfo.arguments.contains("--preview-existing-user") {
            store.updatePreferences { $0.hasOnboarded = true }
        }
        if let screen = ScreenshotPreview.screen { coordinator.prepareScreenshot(screen) }
        if ProcessInfo.processInfo.arguments.contains("--preview"), ProcessInfo.processInfo.arguments.contains("--preview-spending") {
            ScreenshotPreview.seedSpending(store)
        }
        if ProcessInfo.processInfo.arguments.contains("--preview"), ProcessInfo.processInfo.arguments.contains("--preview-scan"), store.scans.isEmpty {
            ScreenshotPreview.seedScan(store)
        }
        _tab = State(initialValue: ScreenshotPreview.tab)
        #endif
        _coordinator = State(initialValue: coordinator)
    }
    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $tab) {
            Tab("Talk", systemImage: "waveform", value: 0) { shell { TalkView(coordinator: coordinator) { tab = 3 } } }
            Tab("Themes", systemImage: "square.grid.2x2", value: 1) {
                shell { ThemesView(coordinator: coordinator, choose: { theme in coordinator.chooseTheme(theme); tab = 0 }, openScans: { tab = 4 }) }
                    // A course screen belongs to one language, so a switch starts the tab from the top.
                    .id(coordinator.language.id)
            }
            Tab("Phrases", systemImage: "bookmark", value: 3) { shell { PhrasesView(coordinator: coordinator) } }
            Tab("Scans", systemImage: "doc.text.viewfinder", value: 4) { shell { ScansView(coordinator: coordinator) { tab = 0 } } }
        }
        .tint(MuralColor.ink)
        .sheet(isPresented: $coordinator.showSettings) { SettingsView(coordinator: coordinator) }
        .sheet(isPresented: $coordinator.showAIConsent, onDismiss: { coordinator.resumeAfterAIConsent() }) {
            AIConsentView(agree: { coordinator.acceptAIConsent() }, decline: { coordinator.declineAIConsent() })
        }
        .fullScreenCover(isPresented: $onboarding) {
            OnboardingView(coordinator: coordinator) { coordinator.store.updatePreferences { $0.hasOnboarded = true }; onboarding = false }
                .readableColumn().background(MuralColor.cream)
        }
        .alert("A little interruption", isPresented: Binding(get: { coordinator.error != nil || coordinator.store.error != nil }, set: { if !$0 { coordinator.error = nil; coordinator.store.error = nil } })) {
            Button("OK", role: .cancel) { coordinator.error = nil; coordinator.store.error = nil }
        } message: { Text(coordinator.error ?? coordinator.store.error ?? "") }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            #if DEBUG && targetEnvironment(simulator)
            if arguments.contains("--preview") && arguments.contains("--preview-onboarding") {
                onboarding = !coordinator.store.preferences.hasOnboarded
                return
            }
            #endif
            onboarding = !coordinator.store.preferences.hasOnboarded && !arguments.contains("--preview") && !AudioVerification.requested
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coordinator.background(); coordinator.store.flush() }
            else if phase == .active { coordinator.resume() }
        }
        #if DEBUG
        .task {
            if AudioVerification.requested { await AudioVerification.run(coordinator) }
            else if ProcessInfo.processInfo.arguments.contains("--ended-conversation") { coordinator.prepareEndedPreview() }
        }
        #endif
    }
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().readableColumn().background(MuralColor.cream).toolbar {
                ToolbarItem(placement: .topBarLeading) { Brand().fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coordinator.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }.toolbarBackground(MuralColor.cream, for: .navigationBar)
        }
    }
}

struct TalkView: View {
    @Bindable var coordinator: ConversationCoordinator
    /// Opens the kept phrases, so the confirmation after saving one leads somewhere.
    var showPhrases: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The conversation the open Sources sheet was taken from, kept so it stays readable if the
    /// screen resets underneath it.
    @State private var sourcesSession: SessionRecord?
    @State private var lookup: WordLookup?
    /// A conversation, running or just ended, is read over the figure instead of below it, so the
    /// figure keeps its full size and the words get the whole stage.
    private var conversing: Bool { coordinator.session != nil }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text(coordinator.selectedTheme?.title ?? coordinator.language.talkTitle)
                        .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(MuralColor.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(MuralColor.surface, in: Capsule()).padding(.top, 12)
                    stage
                    StatusLine(coordinator: coordinator)
                    controls
                    Text(coordinator.microphoneLabel).font(.caption2).foregroundStyle(MuralColor.secondary).padding(.top, 10)
                        .accessibilityIdentifier("microphone-status")
                    Group {
                        if conversing && !coordinator.isRunning {
                            Button("New conversation", systemImage: "arrow.counterclockwise") { coordinator.resetConversation() }
                                .accessibilityIdentifier("new-conversation")
                        } else {
                            Text("Reply in whichever language comes to you.").foregroundStyle(MuralColor.secondary)
                        }
                    }.font(.caption).padding(.top, 6).padding(.bottom, 12)
                    if let notice = coordinator.notice { noticeView(notice) }
                }.padding(.horizontal, 30).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
                // The conversation scrolls inside the stage. The page itself only needs to at the
                // accessibility sizes, where the controls may not fit under a full-size figure.
                .scrollDisabled(conversing && !typeSize.isAccessibilitySize)
        }
        .animation(.smooth(duration: 0.35), value: coordinator.state)
        .animation(.smooth(duration: 0.45), value: conversing)
        .sheet(item: $sourcesSession) { session in TopicSourcesView(topics: session.topics) }
        .sheet(item: $lookup) { item in LookupView(item: item, coordinator: coordinator) }
    }
    /// The figure, with the greeting under it until a conversation starts. Then the figure stays
    /// where it is at full size, blurred and dimmed so it reads as a backdrop, and the conversation
    /// fills the stage in front of it.
    private var stage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            OrbPanel(coordinator: coordinator)
                .blur(radius: conversing ? 7 : 0)
                .opacity(conversing ? 0.6 : 1)
            if !conversing { captionArea }
            Spacer(minLength: 12)
        }
        .overlay { if conversing { conversation } }
    }
    private var conversation: some View {
        GeometryReader { geometry in
            ScrollView {
                captionArea.padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }.transition(.opacity)
    }
    /// A notice that leads somewhere is a control, not a sentence. A footnote-sized label in a
    /// plain button collapses to a hairline tap target, so it is padded and given its own shape.
    @ViewBuilder private func noticeView(_ notice: String) -> some View {
        if coordinator.noticeDestination == .savedPhrases {
            Button(action: showPhrases) {
                HStack(spacing: 5) {
                    Text(notice)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(MuralColor.surface, in: Capsule())
                .contentShape(Capsule())
            }.buttonStyle(.plain).font(.footnote).foregroundStyle(MuralColor.ink)
                .padding(.bottom, 12)
                .accessibilityLabel("\(notice) Open your saved phrases")
                .accessibilityIdentifier("notice-saved-phrases")
        } else {
            Text(notice).font(.footnote).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center).padding(.bottom, 12)
        }
    }
    private var captionArea: some View {
        VStack(spacing: 12) {
            Text(linkedCaption).font(.system(coordinator.assistantPassage == nil ? .largeTitle : .title2, design: .rounded, weight: .medium))
                .tracking(-0.5).multilineTextAlignment(.center).tint(MuralColor.ink)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "mural-word", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let word = components.queryItems?.first?.value else { return .discarded }
                    lookup = WordLookup(word: word, sentence: coordinator.caption); return .handled
                }).accessibilityIdentifier("target-caption")
            ReadingHelp(text: coordinator.caption, language: coordinator.language)
            if coordinator.store.preferences.meaningVisible {
                Text(coordinator.assistantPassage == nil ? MeaningLanguages.greeting(in: coordinator.store.preferences.meaningLanguage) : !coordinator.meaning.isEmpty ? coordinator.meaning : coordinator.translating ? "Finding the meaning…" : "")
                    .font(.subheadline).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("meaning-caption")
                if let error = coordinator.meaningError {
                    VStack(spacing: 6) {
                        Text(error).foregroundStyle(MuralColor.secondary)
                        Button("Try meaning again") { coordinator.retryMeaning() }
                    }.font(.caption).multilineTextAlignment(.center)
                }
            }
            PhraseChips(coordinator: coordinator)
            if let user = coordinator.userPassage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("YOU").font(.system(.caption2, design: .rounded, weight: .medium))
                    Text(String(user.text.suffix(160))).font(.caption)
                }.foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center).padding(.top, 3)
            }
            if coordinator.working { ProgressView("Checking that for you…").font(.caption).tint(MuralColor.secondary) }
            if let sources = coordinator.session?.topics.last?.sources, !sources.isEmpty {
                Button("Sources", systemImage: "link") { sourcesSession = coordinator.session }.font(.caption)
            }
        }.frame(minHeight: typeSize.isAccessibilitySize ? 100 : 105).frame(maxWidth: .infinity)
    }
    private var linkedCaption: AttributedString {
        var result = AttributedString()
        for segment in CaptionWords.segments(coordinator.caption, languageID: coordinator.language.id) {
            var part = AttributedString(segment.text)
            if coordinator.assistantPassage != nil, let word = segment.lookup {
                var components = URLComponents(); components.scheme = "mural-word"; components.host = "lookup"
                components.queryItems = [URLQueryItem(name: "word", value: word)]
                part.link = components.url
            }
            part.foregroundColor = MuralColor.ink; result.append(part)
        }
        return result
    }
    private var controls: some View {
        HStack(alignment: .center, spacing: 27) {
            Button { coordinator.toggleMeaning() } label: {
                VStack(spacing: 6) {
                    Image(systemName: coordinator.store.preferences.meaningVisible ? "captions.bubble.fill" : "captions.bubble")
                        .frame(width: 48, height: 48).modifier(SoftGlass(tint: coordinator.store.preferences.meaningVisible ? MuralColor.selected.opacity(0.7) : MuralColor.surface.opacity(0.4)))
                    Text("Meaning").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(coordinator.store.preferences.meaningVisible ? "Hide meaning subtitles" : "Show meaning subtitles")
                .accessibilityValue(coordinator.store.preferences.meaningVisible ? "On" : "Off")
            Button {
                if coordinator.state == .active { coordinator.toggleMute() }
                else if !coordinator.isRunning { coordinator.start() }
            } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [MuralColor.accent.mix(with: .white, by: 0.12), MuralColor.accent.mix(with: .black, by: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if coordinator.state == .connecting || coordinator.state == .closing { ProgressView().tint(MuralColor.onAccent) }
                    else { Image(systemName: coordinator.isMuted && coordinator.state == .active ? "mic.slash" : "mic").font(.system(size: 28, weight: .regular)).contentTransition(.symbolEffect(.replace)) }
                }.foregroundStyle(MuralColor.onAccent).frame(width: 76, height: 76).shadow(color: MuralColor.accent.opacity(0.35), radius: 12, y: 6)
            }.buttonStyle(.plain).padding(.bottom, 18)
                .disabled(coordinator.state == .connecting || coordinator.state == .closing)
                .accessibilityLabel(coordinator.state == .active ? (coordinator.isMuted ? "Unmute microphone" : "Mute microphone") : "Start conversation")
                .accessibilityIdentifier("start-conversation")
            // Only a running conversation can be ended. The slot stays when there is none, so the
            // microphone keeps its place in the middle.
            Button { coordinator.end() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down").frame(width: 48, height: 48).modifier(SoftGlass())
                    Text("End").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("End conversation")
                .opacity(coordinator.isRunning ? 1 : 0).disabled(!coordinator.isRunning).accessibilityHidden(!coordinator.isRunning)
        }.foregroundStyle(MuralColor.ink)
    }
}

/// The orb is the only part of the talk screen that follows the audio levels, which arrive
/// several times a second. It reads them here rather than in `TalkView`, so a level change
/// redraws the orb instead of the whole screen.
private struct OrbPanel: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One size whether or not a conversation is running: the conversation is drawn over the
    /// figure rather than squeezed in below it.
    private var size: CGSize {
        // A landmark is a whole scene rather than a single shape, so it is given more room.
        let scale: CGFloat = coordinator.language.landmarkID.flatMap { Landmarks.all[$0] } == nil ? 1 : 1.3
        let base = typeSize.isAccessibilitySize ? CGSize(width: 170, height: 180) : CGSize(width: 220, height: 222)
        return CGSize(width: base.width * scale, height: base.height * scale)
    }
    var body: some View {
        LanguageFigure(language: coordinator.language, energy: max(coordinator.outputLevel, coordinator.inputLevel * 0.45), listening: coordinator.state == .active && !coordinator.isMuted, active: coordinator.state != .closing)
            .frame(width: size.width, height: size.height).padding(.vertical, 8)
    }
}

/// What Mural is doing, under the stage so the conversation never covers it.
private struct StatusLine: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        Text(coordinator.status).font(.system(.caption, design: .rounded)).foregroundStyle(MuralColor.secondary)
            .contentTransition(.numericText()).padding(.bottom, 14).accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("conversation-status")
    }
}

struct WordLookup: Identifiable { var id = UUID(); var word: String; var sentence: String }
struct LookupView: View {
    let item: WordLookup
    let coordinator: ConversationCoordinator
    @State private var explanation: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(item.word).font(.system(.largeTitle, design: .rounded, weight: .medium))
                ReadingHelp(text: item.word, language: coordinator.language)
                Text(item.sentence).font(.title3).foregroundStyle(MuralColor.secondary)
                if let explanation { Text(explanation).font(.body).textSelection(.enabled) }
                else if let error { Text(error).foregroundStyle(MuralColor.secondary) }
                else { ProgressView("Finding the meaning…") }
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.cream)
                .navigationTitle("A little meaning").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
            .task { do { explanation = try await coordinator.lookup(word: item.word, sentence: item.sentence) } catch { self.error = error.localizedDescription } }
    }
}
