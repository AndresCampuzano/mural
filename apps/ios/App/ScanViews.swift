import SwiftUI
import PhotosUI
import PDFKit
import AVFoundation
import UniformTypeIdentifiers
import MuralCore

/// The entry on the Themes tab. Scans live in their own tab, so this only leads there.
struct PictureCard: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                Image(systemName: "text.viewfinder").font(.system(size: 26, weight: .light)).foregroundStyle(MuralColor.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("From a picture or PDF").font(.system(.headline, design: .rounded))
                    Text("Scan a page, a menu or a sign once, then talk about it or take tests as often as you like.")
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

// MARK: Scans

/// Every picture and PDF read for the current language. Each was read once; everything done
/// with it afterwards starts from the saved text.
struct ScansView: View {
    let coordinator: ConversationCoordinator
    /// Moves to the Talk tab once a conversation about a scan is set up.
    let talk: () -> Void
    @State private var adding = false
    @State private var opened: UUID?
    @State private var renaming: ScannedFile?
    @State private var deleting: ScannedFile?
    private var store: LearningStore { coordinator.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Scans", title: "Read once,\nuse often.",
                            subtitle: "Mural keeps what it read from each picture or PDF, so talking about it or taking another test never sends the file again.")
                Button { adding = true } label: {
                    HStack { Image(systemName: "plus.viewfinder"); Text("New scan"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).background(MuralColor.peach, in: RoundedRectangle(cornerRadius: 26))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("scan-new")
                if store.scans.isEmpty {
                    Text("Your \(store.language.name) scans will appear here.").font(.subheadline).foregroundStyle(MuralColor.secondary)
                }
                ForEach(store.scans) { scan in row(scan) }
            }.padding(24)
        }.foregroundStyle(MuralColor.ink)
            .sheet(isPresented: $adding) { NewScanView(coordinator: coordinator) { opened = $0 } }
            .navigationDestination(item: $opened) { id in ScanDetailView(coordinator: coordinator, scanID: id, talk: talk) }
            .renameAlert(item: $renaming, name: \.name) { scan, name in store.updateScan(scan.id) { $0.rename(name) } }
            .confirmationDialog("Delete this scan?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { scan in
                Button("Delete scan", role: .destructive) { store.deleteScan(scan.id) }
            } message: { _ in Text("This removes what Mural read from it, its tests and their results. Conversations you already had stay in Past conversations.") }
    }

    private func row(_ scan: ScannedFile) -> some View {
        HStack(spacing: 14) {
            Button { opened = scan.id } label: {
                HStack(spacing: 14) {
                    ScanThumbnail(scan: scan, side: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.name).font(.system(.headline, design: .rounded)).multilineTextAlignment(.leading)
                        Text("\(scan.detail) · \(scan.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(MuralColor.secondary)
                        Text(scan.practices.isEmpty ? "Nothing practised yet" : scan.practices.count == 1 ? "1 saved practice" : "\(scan.practices.count) saved practices")
                            .font(.caption2).foregroundStyle(MuralColor.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("scan-row")
            Menu {
                Button("Rename", systemImage: "pencil") { renaming = scan }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = scan }
            } label: { Image(systemName: "ellipsis").padding(12).contentShape(Rectangle()) }
                .accessibilityLabel("More for \(scan.name)")
        }.padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
            .contextMenu {
                Button("Rename", systemImage: "pencil") { renaming = scan }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = scan }
            }
    }
}

struct ScanThumbnail: View {
    let scan: ScannedFile
    let side: CGFloat
    var body: some View {
        Group {
            if let data = scan.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: scan.kind == .pdf ? "doc.text" : "photo").font(.system(size: side * 0.35, weight: .light))
                    .foregroundStyle(MuralColor.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(MuralColor.butter)
            }
        }.frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: side * 0.22)).accessibilityHidden(true)
    }
}

// MARK: New scan

/// A picture or PDF prepared for sending: downscaled, trimmed, and held in memory only.
struct PreparedPicture {
    var attachment: APIAttachment
    var kind: ScannedFile.Kind
    var preview: UIImage
    var detail: String

    static let maximumSide: CGFloat = 2048
    static let maximumPages = 10
    static let maximumBytes = 20_000_000

    static func image(_ image: UIImage) -> PreparedPicture? {
        let resized = scaled(image, to: maximumSide)
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return PreparedPicture(attachment: .jpeg(data), kind: .picture, preview: resized, detail: "Picture")
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
        return PreparedPicture(attachment: .pdf(sent, filename: filename.isEmpty ? "document.pdf" : filename), kind: .pdf, preview: preview, detail: detail)
    }

    /// A small square-ish JPEG to recognise the scan by in the list, within the archive's limit.
    var thumbnail: Data? {
        let small = Self.scaled(preview, to: 240)
        for quality in [0.7, 0.5, 0.3] {
            if let data = small.jpegData(compressionQuality: quality), data.count <= ScannedFile.maximumThumbnailBytes { return data }
        }
        return nil
    }

    private static func scaled(_ image: UIImage, to side: CGFloat) -> UIImage {
        let scale = min(1, side / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
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

struct NewScanView: View {
    let coordinator: ConversationCoordinator
    let scanned: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picture: PreparedPicture?
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var files = false
    @State private var loading = false
    @State private var error: String?
    private var language: LanguageModule { coordinator.language }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "New scan", title: "Something to\nlearn from.",
                                subtitle: "A page, a menu, a sign or a PDF. Mural reads the \(language.name) in it, or names what it shows, and keeps what it read.")
                    sources
                    if let picture { preview(picture) }
                    if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary).accessibilityIdentifier("picture-error") }
                    Text("The file is sent to OpenAI once to read it. Mural keeps the text it read and a small thumbnail on this device, never the file itself.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                }.padding(26).readableColumn()
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .interactiveDismissDisabled(loading)
        .onChange(of: photo) { _, item in if let item { loadPhoto(item) } }
        .fullScreenCover(isPresented: $camera) { CameraPicker { image in use(PreparedPicture.image(image)) }.ignoresSafeArea() }
        .fileImporter(isPresented: $files, allowedContentTypes: [.image, .pdf]) { result in loadFile(result) }
    }

    private var sources: some View {
        HStack(spacing: 10) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: { sourceLabel("Camera", "camera") }.buttonStyle(.plain).accessibilityIdentifier("picture-camera")
            }
            PhotosPicker(selection: $photo, matching: .images) { sourceLabel("Photos", "photo.on.rectangle") }
                .buttonStyle(.plain).accessibilityIdentifier("picture-photos")
            Button { files = true } label: { sourceLabel("Files", "doc") }.buttonStyle(.plain).accessibilityIdentifier("picture-files")
        }.disabled(loading)
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
            Button { read(picture) } label: {
                HStack { Text(loading ? "Reading…" : "Read and keep it"); Spacer(); if loading { ProgressView() } else { Image(systemName: "text.viewfinder") } }
                    .font(.headline).padding(18).background(MuralColor.orange, in: Capsule())
            }.buttonStyle(.plain).disabled(loading).accessibilityIdentifier("picture-read")
        }
    }
    private func use(_ prepared: PreparedPicture?) {
        guard let prepared else { error = PictureInputError.unreadable.localizedDescription; return }
        picture = prepared; error = nil
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
                let file = try await coordinator.scan(picture.attachment, kind: picture.kind, detail: picture.detail, thumbnail: picture.thumbnail)
                loading = false
                dismiss(); scanned(file.id)
            } catch is CancellationError { loading = false
            } catch { self.error = error.localizedDescription; loading = false }
        }
    }
}

// MARK: One scan

struct ScanDetailView: View {
    let coordinator: ConversationCoordinator
    let scanID: UUID
    let talk: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activity: PictureActivity = .conversation
    @State private var level: GuidanceLevel = .inAtTheDeepEnd
    @State private var pace: SpeechPace = .natural
    @State private var savedWords: String?
    @State private var openTest: UUID?
    @State private var making = false
    @State private var error: String?
    @State private var renamingScan = false
    @State private var deletingScan = false
    @State private var renaming: SavedPractice?
    @State private var deleting: SavedPractice?
    private var store: LearningStore { coordinator.store }
    private var language: LanguageModule { coordinator.language }

    var body: some View {
        Group {
            if let scan = store.scan(scanID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(scan)
                        content(scan)
                        practices(scan)
                        newPractice(scan)
                    }.padding(24)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Rename", systemImage: "pencil") { renamingScan = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { deletingScan = true }
                        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Scan options")
                    }
                }
                .renameAlert(isPresented: $renamingScan, current: scan.name) { name in store.updateScan(scanID) { $0.rename(name) } }
                .renameAlert(item: $renaming, name: \.name) { practice, name in store.updateScan(scanID) { $0.renamePractice(practice.id, to: name) } }
                .confirmationDialog("Delete this scan?", isPresented: $deletingScan, titleVisibility: .visible) {
                    Button("Delete scan", role: .destructive) { dismiss(); store.deleteScan(scanID) }
                } message: { Text("This removes what Mural read from it, its tests and their results.") }
                .confirmationDialog("Delete this practice?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                    titleVisibility: .visible, presenting: deleting) { practice in
                    Button("Delete", role: .destructive) { store.updateScan(scanID) { $0.removePractice(practice.id) } }
                } message: { practice in Text(practice.activity == .writtenTest ? "Its questions and results will be removed." : "Its level and pace will be removed.") }
            } else {
                ContentUnavailableView("This scan was deleted", systemImage: "doc.text.viewfinder")
            }
        }
        .foregroundStyle(MuralColor.ink).background(MuralColor.cream)
        .navigationDestination(item: $openTest) { id in PictureTestView(coordinator: coordinator, scanID: scanID, practiceID: id) }
        .onAppear { level = store.preferences.guidanceLevel; pace = store.preferences.pace }
    }

    private func header(_ scan: ScannedFile) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ScanThumbnail(scan: scan, side: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(scan.name).font(.system(.title2, design: .rounded, weight: .semibold)).accessibilityIdentifier("scan-name")
                Text("\(scan.detail) · \(scan.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(MuralColor.secondary)
            }
        }
    }

    private func content(_ scan: ScannedFile) -> some View {
        let study = scan.study
        return VStack(alignment: .leading, spacing: 16) {
            Text(study.summary).font(.body)
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
        }
    }

    @ViewBuilder private func practices(_ scan: ScannedFile) -> some View {
        if !scan.practices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                label("Your practice")
                ForEach(scan.practices.reversed()) { practice in practiceRow(practice, scan: scan) }
            }
        }
    }

    private func practiceRow(_ practice: SavedPractice, scan: ScannedFile) -> some View {
        HStack(spacing: 12) {
            Button { open(practice, scan: scan) } label: {
                HStack(spacing: 12) {
                    Image(systemName: practice.activity.symbol).font(.system(size: 20, weight: .light)).frame(width: 28).foregroundStyle(MuralColor.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(practice.name).font(.system(.headline, design: .rounded)).multilineTextAlignment(.leading)
                        Text(summary(practice)).font(.caption).foregroundStyle(MuralColor.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: practice.activity == .conversation ? "play.fill" : "chevron.right").font(.caption).foregroundStyle(MuralColor.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(practice.activity == .conversation && coordinator.isRunning)
                .accessibilityIdentifier("practice-\(practice.activity.rawValue)")
            Menu {
                Button("Rename", systemImage: "pencil") { renaming = practice }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = practice }
            } label: { Image(systemName: "ellipsis").padding(10).contentShape(Rectangle()) }
                .accessibilityLabel("More for \(practice.name)")
        }.padding(14).background(MuralColor.panels[practice.activity == .conversation ? 0 : 1].opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
    }

    private func summary(_ practice: SavedPractice) -> String {
        switch practice.activity {
        case .conversation:
            return [practice.level.title, practice.pace?.title].compactMap { $0 }.joined(separator: " · ")
        case .writtenTest:
            var parts = [practice.level.title, "\(practice.questions.count) questions"]
            if let best = practice.best {
                parts.append(practice.attempts.count == 1 ? "taken once" : "taken \(practice.attempts.count) times")
                parts.append("best \(best.score.formatted(.number.precision(.fractionLength(0...1)))) of \(best.total)")
            }
            return parts.joined(separator: " · ")
        }
    }

    private func newPractice(_ scan: ScannedFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            label("New practice")
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
                                Text(option.detail(language: language, meaningLanguage: scan.study.meaningLanguage)).font(.caption).foregroundStyle(MuralColor.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(level == option ? .isSelected : []).accessibilityIdentifier("picture-level-\(option.rawValue)")
                }
            }
            // Pace is how fast Mural speaks, so it belongs to a conversation only.
            if activity == .conversation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speaking pace").font(.subheadline.weight(.medium))
                    Picker("Speaking pace", selection: $pace) {
                        ForEach(SpeechPace.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("picture-pace")
                }
            }
            Button { create(scan) } label: {
                HStack {
                    Text(making ? "Writing your test…" : activity == .conversation ? "Save and set up the conversation" : "Make and save the test")
                    Spacer(); if making { ProgressView() } else { Image(systemName: activity == .conversation ? "waveform" : "arrow.right") }
                }.font(.headline).padding(18).background(MuralColor.orange, in: Capsule())
            }.buttonStyle(.plain).disabled(making || (activity == .conversation && coordinator.isRunning)).accessibilityIdentifier("picture-start")
            if activity == .conversation && coordinator.isRunning {
                Text("End the current conversation first.").font(.caption).foregroundStyle(MuralColor.secondary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary) }
            Text(activity == .conversation
                 ? "Setting up a conversation sends nothing. The conversation itself uses your OpenAI account as usual."
                 : "Writing a test uses your OpenAI account once. Retaking it is free, except marking written answers that don’t match exactly.")
                .font(.caption2).foregroundStyle(MuralColor.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.butter.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(.caption2, design: .rounded, weight: .medium)).tracking(1.2).foregroundStyle(MuralColor.secondary)
    }

    private func open(_ practice: SavedPractice, scan: ScannedFile) {
        switch practice.activity {
        case .conversation:
            coordinator.practice(scan.study, level: practice.level, pace: practice.pace ?? store.preferences.pace); talk()
        case .writtenTest: openTest = practice.id
        }
    }
    private func create(_ scan: ScannedFile) {
        error = nil
        switch activity {
        case .conversation:
            guard let practice = coordinator.saveConversation(scanID: scan.id, level: level, pace: pace) else { return }
            open(practice, scan: scan)
        case .writtenTest:
            making = true
            Task {
                do { openTest = try await coordinator.makeTest(scanID: scan.id, level: level).id }
                catch is CancellationError {}
                catch { self.error = error.localizedDescription }
                making = false
            }
        }
    }
}

// MARK: Written test

/// A saved written test, which can be taken again and again. Answers are marked here and never
/// reach the learning record: typing a reply after studying the words is not retrieval in
/// conversation.
struct PictureTestView: View {
    let coordinator: ConversationCoordinator
    let scanID: UUID
    let practiceID: UUID
    @State private var responses: [String] = []
    @State private var grades: [GradedAnswer?] = []
    @State private var marking = false
    @State private var error: String?
    @State private var speaker = PassageSpeaker()

    private var store: LearningStore { coordinator.store }
    private var scan: ScannedFile? { store.scan(scanID) }
    private var practice: SavedPractice? { scan?.practice(id: practiceID) }
    private var language: LanguageModule { scan.flatMap { LanguageRegistry.module(for: $0.languageID) } ?? coordinator.language }
    private var marked: Bool { !grades.isEmpty && grades.allSatisfy { $0 != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let practice {
                    PageHeading(eyebrow: "Written test · \(practice.level.title)", title: practice.name, subtitle: history(practice))
                    if marked {
                        Text("\(TestGrader.score(grades).formatted(.number.precision(.fractionLength(0...1)))) of \(practice.questions.count)")
                            .font(.system(.title, design: .rounded, weight: .semibold)).accessibilityIdentifier("picture-test-score")
                    }
                    if responses.count == practice.questions.count {
                        ForEach(Array(practice.questions.enumerated()), id: \.element.id) { index, question in questionCard(index, question) }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary).accessibilityIdentifier("picture-test-error") }
                    if marked {
                        Button("Take it again", systemImage: "arrow.counterclockwise") { reset(practice) }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).background(MuralColor.peach, in: Capsule())
                            .accessibilityIdentifier("picture-test-retake")
                    } else {
                        Button { check() } label: {
                            HStack { Text(marking ? "Checking…" : "Check answers"); Spacer(); if marking { ProgressView() } else { Image(systemName: "checkmark") } }
                                .font(.headline).padding(18).background(MuralColor.orange, in: Capsule())
                        }.buttonStyle(.plain).disabled(marking).accessibilityIdentifier("picture-test-check")
                    }
                    Text("This test is practice. It doesn’t change your recall bars: those are earned by using words in conversation.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                } else {
                    ContentUnavailableView("This test was deleted", systemImage: "pencil.and.list.clipboard")
                }
            }.padding(26).readableColumn()
        }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if let practice, responses.count != practice.questions.count { reset(practice) } }
            .onDisappear { speaker.stop() }
    }

    private func history(_ practice: SavedPractice) -> String {
        guard let best = practice.best else { return "Answer what you can, then check. Tap the speaker to hear a passage." }
        let times = practice.attempts.count == 1 ? "Taken once" : "Taken \(practice.attempts.count) times"
        return "\(times) · best \(best.score.formatted(.number.precision(.fractionLength(0...1)))) of \(best.total)"
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
                    Button { listen(question.passage) } label: {
                        Image(systemName: "speaker.wave.2").font(.title3).padding(12)
                            .background(.white.opacity(0.8), in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Listen").accessibilityIdentifier("picture-test-listen")
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

    private func listen(_ text: String) {
        error = nil
        // A running conversation owns the audio session, so a passage waits until it ends.
        guard !coordinator.isRunning else { error = "Passages can be heard once the current conversation ends."; return }
        if !speaker.speak(text, locale: language.locale, pace: store.preferences.pace) {
            error = "No \(language.name) voice is installed. Add one in Settings → Accessibility → Spoken Content → Voices."
        }
    }
    private func reset(_ practice: SavedPractice) {
        responses = Array(repeating: "", count: practice.questions.count); grades = []; error = nil
    }
    private func check() {
        marking = true; error = nil
        Task {
            do { grades = try await coordinator.grade(scanID: scanID, practiceID: practiceID, responses: responses) }
            catch is CancellationError {}
            catch { self.error = error.localizedDescription }
            marking = false
        }
    }
}

/// Reads a passage aloud with the system voice for the module's locale, at the chosen pace.
///
/// A conversation leaves the shared audio session in voice-chat mode, and a fresh launch leaves
/// it in the default category that the silent setting mutes; either can swallow synthesized
/// speech. So each passage claims a playback session first and hands it back when it ends.
@MainActor final class PassageSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    override init() { super.init(); synthesizer.delegate = self }

    /// Returns false when no voice for the language is installed.
    @discardableResult func speak(_ text: String, locale: String, pace: SpeechPace) -> Bool {
        guard let voice = Self.voice(for: locale) else { return false }
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(pace.speed)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        synthesizer.speak(utterance)
        return true
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    /// The exact locale when it is installed, otherwise any voice for the same language.
    static func voice(for locale: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: locale) { return exact }
        let prefix = String(locale.prefix { $0 != "-" && $0 != "_" }).lowercased()
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.lowercased().hasPrefix(prefix) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { release() }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { release() }
    private nonisolated func release() {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

// MARK: Renaming

extension View {
    /// Asks for a new name for `item`, starting from its current one.
    func renameAlert<Item: Identifiable>(item: Binding<Item?>, name: KeyPath<Item, String>, save: @escaping (Item, String) -> Void) -> some View {
        // Captured now, because the alert clears the binding as it closes.
        let value = item.wrappedValue
        return modifier(RenameAlert(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                                    current: value?[keyPath: name] ?? "") { text in if let value { save(value, text) } })
    }
    func renameAlert(isPresented: Binding<Bool>, current: String, save: @escaping (String) -> Void) -> some View {
        modifier(RenameAlert(isPresented: isPresented, current: current, save: save))
    }
}

private struct RenameAlert: ViewModifier {
    @Binding var isPresented: Bool
    let current: String
    let save: (String) -> Void
    @State private var text = ""
    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, shown in if shown { text = current } }
            .alert("Rename", isPresented: $isPresented) {
                TextField("Name", text: $text)
                Button("Save") { save(text) }.disabled(ScannedFile.cleanName(text) == nil)
                Button("Cancel", role: .cancel) {}
            }
    }
}
