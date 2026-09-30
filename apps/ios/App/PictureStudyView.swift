import SwiftUI
import PhotosUI
import PDFKit
import AVFoundation
import UniformTypeIdentifiers
import MuralCore

/// The entry on the Themes tab: study from a photo, a picture already on the device, or a PDF.
struct PictureCard: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                Image(systemName: "text.viewfinder").font(.system(size: 26, weight: .light)).foregroundStyle(MuralColor.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("From a picture or PDF").font(.system(.headline, design: .rounded))
                    Text("Photograph a page, a menu or a sign, and talk about it or take a short test.")
                        .font(.caption).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(MuralColor.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(MuralColor.lilac.opacity(0.8), in: RoundedRectangle(cornerRadius: 26))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("picture-card")
    }
}

/// A picture or PDF prepared for sending: downscaled, trimmed, and held in memory only.
struct PreparedPicture {
    var attachment: APIAttachment
    var preview: UIImage
    var detail: String

    static let maximumSide: CGFloat = 2048
    static let maximumPages = 10
    static let maximumBytes = 20_000_000

    static func image(_ image: UIImage) -> PreparedPicture? {
        let scale = min(1, maximumSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return PreparedPicture(attachment: .jpeg(data), preview: resized, detail: "Picture")
    }

    /// Long documents are cut to their first pages, which keeps the request small and the test
    /// about something the learner can actually read through.
    static func pdf(_ data: Data, filename: String) throws -> PreparedPicture {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw PictureInputError.unreadable }
        var sent = data, detail = document.pageCount == 1 ? "PDF · 1 page" : "PDF · \(document.pageCount) pages"
        if document.pageCount > maximumPages {
            let trimmed = PDFDocument()
            for index in 0..<maximumPages { if let page = document.page(at: index) { trimmed.insert(page, at: trimmed.pageCount) } }
            guard let data = trimmed.dataRepresentation() else { throw PictureInputError.unreadable }
            sent = data; detail = "PDF · first \(maximumPages) of \(document.pageCount) pages"
        }
        guard sent.count <= maximumBytes else { throw PictureInputError.tooLarge }
        let preview = document.page(at: 0)?.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox) ?? UIImage()
        return PreparedPicture(attachment: .pdf(sent, filename: filename.isEmpty ? "document.pdf" : filename), preview: preview, detail: detail)
    }
}

enum PictureInputError: LocalizedError {
    case unreadable, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "Mural couldn’t open that file. Try a picture or a different PDF."
        case .tooLarge: "That PDF is too large to send. Try a shorter one, or photograph the page you need."
        }
    }
}

struct PictureStudyView: View {
    let coordinator: ConversationCoordinator
    /// Called when a conversation has been set up, so the caller can move to the Talk tab.
    let practise: (PictureStudy, GuidanceLevel, SpeechPace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picture: PreparedPicture?
    @State private var study: PictureStudy?
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var files = false
    @State private var loading = false
    @State private var error: String?
    @State private var activity: PictureActivity = .conversation
    @State private var level: GuidanceLevel = .inAtTheDeepEnd
    @State private var pace: SpeechPace = .natural
    @State private var savedWords: String?
    @State private var testing = false

    private var language: LanguageModule { coordinator.language }
    private var meaningLanguage: String { coordinator.store.preferences.meaningLanguage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "From a picture", title: "Something to\nlearn from.",
                                subtitle: "A page, a menu, a sign or a PDF. Mural reads the \(language.name) in it, or names what it shows.")
                    sources
                    if let picture { preview(picture) }
                    if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary).accessibilityIdentifier("picture-error") }
                    if let study { studied(study) }
                    Text("Your picture or PDF is sent to OpenAI to read it and is not kept on this device or saved with your conversations.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                }.padding(26).readableColumn()
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .navigationDestination(isPresented: $testing) {
                    if let study { PictureTestView(coordinator: coordinator, study: study, level: level, pace: pace) }
                }
        }
        .onAppear { level = coordinator.store.preferences.guidanceLevel; pace = coordinator.store.preferences.pace }
        .onChange(of: photo) { _, item in if let item { loadPhoto(item) } }
        .fullScreenCover(isPresented: $camera) { CameraPicker { image in use(PreparedPicture.image(image)) }.ignoresSafeArea() }
        .fileImporter(isPresented: $files, allowedContentTypes: [.image, .pdf]) { result in loadFile(result) }
    }

    private var sources: some View {
        HStack(spacing: 10) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sourceButton("Camera", "camera") { camera = true }.accessibilityIdentifier("picture-camera")
            }
            PhotosPicker(selection: $photo, matching: .images) { sourceLabel("Photos", "photo.on.rectangle") }
                .buttonStyle(.plain).accessibilityIdentifier("picture-photos")
            sourceButton("Files", "doc") { files = true }.accessibilityIdentifier("picture-files")
        }.disabled(loading)
    }
    private func sourceButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { sourceLabel(title, symbol) }.buttonStyle(.plain)
    }
    private func sourceLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light))
            Text(title).font(.subheadline)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
    }

    private func preview(_ picture: PreparedPicture) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(uiImage: picture.preview).resizable().scaledToFit().frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18)).frame(maxWidth: .infinity)
                .accessibilityLabel(picture.detail)
            Text(picture.detail).font(.caption).foregroundStyle(MuralColor.secondary)
            if study == nil {
                Button { read(picture) } label: {
                    HStack { Text(loading ? "Reading…" : "Read it"); Spacer(); if loading { ProgressView() } else { Image(systemName: "text.viewfinder") } }
                        .font(.headline).padding(18).background(MuralColor.peach, in: Capsule())
                }.buttonStyle(.plain).disabled(loading).accessibilityIdentifier("picture-read")
            }
        }
    }

    private func studied(_ study: PictureStudy) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(study.title).font(.system(.title2, design: .rounded, weight: .semibold))
                Text(study.summary).font(.body)
            }
            if !study.targetText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("In the picture")
                    Text(study.targetText).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                    ReadingHelp(text: study.targetText, language: language)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
            }
            if !study.vocabulary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    label("Words")
                    ForEach(study.vocabulary, id: \.self) { term in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(term.text).font(.system(.headline, design: .rounded)).textSelection(.enabled)
                            if !term.meaning.isEmpty { Text(term.meaning).font(.subheadline).foregroundStyle(MuralColor.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Save words to Phrases", systemImage: "bookmark") {
                        let added = coordinator.savePictureWords(study)
                        savedWords = added == 0 ? "These words are already in your phrases." : added == 1 ? "Saved 1 word to your phrases." : "Saved \(added) words to your phrases."
                    }.font(.subheadline).padding(.vertical, 6).contentShape(Rectangle()).accessibilityIdentifier("picture-save-words")
                    if let savedWords { Text(savedWords).font(.caption).foregroundStyle(MuralColor.secondary) }
                    Text("Phrases are a notebook: saving one doesn’t earn a recall bar.").font(.caption2).foregroundStyle(MuralColor.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.sage.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
            }
            if study.isUsable { options(study) }
            Button("Choose another", systemImage: "arrow.counterclockwise") { self.study = nil; picture = nil; photo = nil; error = nil; savedWords = nil }
                .font(.subheadline).padding(.vertical, 6).contentShape(Rectangle())
        }
    }

    private func options(_ study: PictureStudy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            label("Practise it")
            Picker("Activity", selection: $activity) {
                ForEach(PictureActivity.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("picture-activity")
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty").font(.subheadline.weight(.medium))
                ForEach(GuidanceLevel.allCases) { option in
                    Button { level = option } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: level == option ? "largecircle.fill.circle" : "circle").foregroundStyle(level == option ? MuralColor.orange : MuralColor.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.subheadline.weight(.medium))
                                Text(option.detail(language: language, meaningLanguage: meaningLanguage)).font(.caption).foregroundStyle(MuralColor.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(level == option ? .isSelected : []).accessibilityIdentifier("picture-level-\(option.rawValue)")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Speaking pace").font(.subheadline.weight(.medium))
                Picker("Speaking pace", selection: $pace) {
                    ForEach(SpeechPace.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("picture-pace")
                Text(activity == .conversation ? "How fast Mural speaks in this conversation." : "How fast questions are read aloud when you tap listen.")
                    .font(.caption).foregroundStyle(MuralColor.secondary)
            }
            Button { start(study) } label: {
                HStack {
                    Text(activity == .conversation ? "Set up the conversation" : "Make the test")
                    Spacer(); Image(systemName: activity == .conversation ? "waveform" : "arrow.right")
                }.font(.headline).padding(18).background(MuralColor.orange, in: Capsule())
            }.buttonStyle(.plain).disabled(activity == .conversation && coordinator.isRunning).accessibilityIdentifier("picture-start")
            if activity == .conversation && coordinator.isRunning {
                Text("End the current conversation first.").font(.caption).foregroundStyle(MuralColor.secondary)
            }
            Text("These choices apply to this picture only; your settings stay as they are.").font(.caption2).foregroundStyle(MuralColor.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.butter.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(.caption2, design: .rounded, weight: .medium)).tracking(1.2).foregroundStyle(MuralColor.secondary)
    }

    private func start(_ study: PictureStudy) {
        switch activity {
        case .conversation: practise(study, level, pace); dismiss()
        case .writtenTest: testing = true
        }
    }
    private func use(_ prepared: PreparedPicture?) {
        guard let prepared else { error = PictureInputError.unreadable.localizedDescription; return }
        picture = prepared; study = nil; error = nil; savedWords = nil
    }
    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw PictureInputError.unreadable }
                use(PreparedPicture.image(image))
            } catch { self.error = PictureInputError.unreadable.localizedDescription }
        }
    }
    private func loadFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                use(try PreparedPicture.pdf(data, filename: url.lastPathComponent))
            } else if let image = UIImage(data: data) {
                use(PreparedPicture.image(image))
            } else { throw PictureInputError.unreadable }
        } catch { self.error = error.localizedDescription }
    }
    private func read(_ picture: PreparedPicture) {
        loading = true; error = nil
        Task {
            do {
                let result = try await coordinator.readPicture(picture.attachment)
                study = result
                if !result.isUsable { error = "Mural didn’t find anything to learn from in this one. Try a clearer picture." }
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

/// The camera, for photographing a page or a sign on the spot.
struct CameraPicker: UIViewControllerRepresentable {
    let picked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.picked(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// A short written test from a picture. Answers are marked here and never reach the learning
/// record: typing a reply after studying the words is not retrieval in conversation.
struct PictureTestView: View {
    let coordinator: ConversationCoordinator
    let study: PictureStudy
    let level: GuidanceLevel
    let pace: SpeechPace
    @State private var test: PictureTest?
    @State private var responses: [String] = []
    @State private var grades: [GradedAnswer?] = []
    @State private var loading = false
    @State private var marking = false
    @State private var error: String?
    @State private var speaker = PassageSpeaker()

    private var language: LanguageModule { LanguageRegistry.module(for: study.languageID) ?? coordinator.language }
    private var marked: Bool { !grades.isEmpty && grades.allSatisfy { $0 != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Written test · \(level.title)", title: study.title, subtitle: "Answer what you can, then check. Tap listen to hear a passage read aloud.")
                if loading { HStack(spacing: 12) { ProgressView(); Text("Writing your test…") }.foregroundStyle(MuralColor.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary).accessibilityIdentifier("picture-test-error") }
                if let test {
                    if marked {
                        let score = TestGrader.score(grades)
                        Text("\(score.formatted(.number.precision(.fractionLength(0...1)))) of \(test.questions.count)")
                            .font(.system(.title, design: .rounded, weight: .semibold)).accessibilityIdentifier("picture-test-score")
                    }
                    ForEach(Array(test.questions.enumerated()), id: \.element.id) { index, question in questionCard(index, question) }
                    if marked {
                        Button("Another test", systemImage: "arrow.counterclockwise") { make() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).background(MuralColor.peach, in: Capsule())
                    } else {
                        Button { check(test) } label: {
                            HStack { Text(marking ? "Checking…" : "Check answers"); Spacer(); if marking { ProgressView() } else { Image(systemName: "checkmark") } }
                                .font(.headline).padding(18).background(MuralColor.orange, in: Capsule())
                        }.buttonStyle(.plain).disabled(marking).accessibilityIdentifier("picture-test-check")
                    }
                    Text("This test is practice. It doesn’t change your recall bars: those are earned by using words in conversation.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                } else if !loading {
                    Button("Try again", systemImage: "arrow.counterclockwise") { make() }.font(.headline)
                }
            }.padding(26).readableColumn()
        }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
            .navigationBarTitleDisplayMode(.inline)
            .task { if test == nil { make() } }
            .onDisappear { speaker.stop() }
    }

    private func questionCard(_ index: Int, _ question: TestQuestion) -> some View {
        let grade = grades.indices.contains(index) ? grades[index] : nil
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(index + 1). \(question.prompt)").font(.system(.headline, design: .rounded))
            if !question.passage.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.passage).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                        ReadingHelp(text: question.passage, language: language)
                    }
                    Spacer(minLength: 0)
                    Button { speaker.speak(question.passage, locale: language.locale, pace: pace) } label: {
                        Image(systemName: "speaker.wave.2").padding(10).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Listen")
                }
            }
            switch question.kind {
            case .choice:
                ForEach(question.options, id: \.self) { option in
                    let chosen = responses[index] == option
                    Button { if grade == nil { responses[index] = option } } label: {
                        HStack {
                            Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                            Text(option).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if grade != nil && option == question.answer { Image(systemName: "checkmark").foregroundStyle(MuralColor.orange) }
                        }.padding(.horizontal, 14).padding(.vertical, 11)
                            .background(chosen ? MuralColor.peach : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
                }
            case .written:
                TextField("Your answer", text: $responses[index], axis: .vertical)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14)).disabled(grade != nil)
            }
            if let grade {
                VStack(alignment: .leading, spacing: 4) {
                    Text(grade.verdict.title).font(.subheadline.weight(.semibold)).foregroundStyle(grade.verdict == .correct ? MuralColor.ink : MuralColor.orange)
                    if !grade.feedback.isEmpty { Text(grade.feedback).font(.subheadline) }
                    if grade.verdict != .correct && question.kind == .written { Text("One answer: \(question.answer)").font(.subheadline).textSelection(.enabled) }
                    if !question.explanation.isEmpty { Text(question.explanation).font(.caption).foregroundStyle(MuralColor.secondary) }
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.panels[index % 4].opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
    }

    private func make() {
        loading = true; error = nil; test = nil; grades = []
        Task {
            do {
                let made = try await coordinator.makeTest(from: study, level: level)
                responses = Array(repeating: "", count: made.questions.count); test = made
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func check(_ test: PictureTest) {
        marking = true; error = nil
        Task {
            do { grades = try await coordinator.grade(test, responses: responses, study: study) }
            catch is CancellationError {}
            catch { self.error = error.localizedDescription }
            marking = false
        }
    }
}

/// Reads a passage aloud with the system voice for the module's locale, at the chosen pace.
@MainActor @Observable final class PassageSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String, locale: String, pace: SpeechPace) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(pace.speed)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
