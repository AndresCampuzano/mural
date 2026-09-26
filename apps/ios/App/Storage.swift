import Foundation
import SwiftData
import Security
import Observation
import MuralCore

@Model final class StoredArchive {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "mural-v1"; self.payload = payload }
}

@MainActor @Observable final class LearningStore {
    private(set) var archive = Archive()
    var error: String?
    @ObservationIgnored var onSessionInvalidation: ((UUID) -> Void)?
    let container: ModelContainer
    private var document: StoredArchive
    private let migrationBackupURL: URL?
    /// Every change re-encodes the whole archive, so conversation-rate writes are counted here
    /// and written once they settle. `version` is the change the archive is on; `writtenVersion`
    /// is the newest change already on disk.
    private var version = 0
    private var writtenVersion = 0
    private var persistTask: Task<Void, Never>?
    init(inMemory: Bool = false) throws {
        migrationBackupURL = inMemory ? nil : URL.applicationSupportDirectory
            .appendingPathComponent("Mural", isDirectory: true)
            .appendingPathComponent("before-language-modules.json")
        container = try ModelContainer(for: StoredArchive.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
        let context = container.mainContext
        if let existing = try context.fetch(FetchDescriptor<StoredArchive>()).first {
            document = existing
            archive = try Archive.decode(existing.payload)
            if let backup = migrationBackupURL,
               let root = try JSONSerialization.jsonObject(with: existing.payload) as? [String: Any], root["schemaVersion"] as? Int == 1 {
                let directory = backup.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try existing.payload.write(to: backup, options: [.atomic, .completeFileProtection])
                }
            }
            for i in archive.sessions.indices where archive.sessions[i].endedAt == nil {
                archive.sessions[i].endedAt = .now; archive.sessions[i].endReason = "App closed before finalization"
            }
        } else {
            document = StoredArchive(payload: try Archive().encoded()); context.insert(document)
        }
        persist()
    }
    var preferences: Preferences { archive.preferences }
    var language: LanguageModule { LanguageRegistry.module(for: preferences.learningLanguageID)! }
    var sessions: [SessionRecord] { archive.sessions.sorted { $0.startedAt > $1.startedAt } }
    var learningSessions: [SessionRecord] { sessions.filter { $0.languageID == language.id } }
    var learner: LearnerState { LearningEngine.project(archive.sessions, languageID: language.id, hiddenWords: archive.preferences.hiddenWords) }
    func selectLanguage(_ id: String) {
        guard LanguageRegistry.module(for: id) != nil else { return }
        archive.preferences.learningLanguageID = id; persist()
    }
    func updatePreferences(_ change: (inout Preferences) -> Void) { change(&archive.preferences); persist() }
    /// A running conversation saves its transcript a few times a second. Coalesce those writes
    /// rather than re-encoding the whole archive each time; `flush()` makes them durable.
    func save(_ session: SessionRecord) {
        if let i = archive.sessions.firstIndex(where: { $0.id == session.id }) { archive.sessions[i] = session }
        else { archive.sessions.append(session) }
        schedulePersist()
    }
    /// Writes a coalesced conversation save at once. Called when a conversation ends and when
    /// the app leaves the foreground, so nothing waits on a timer to become durable.
    func flush() {
        guard version > writtenVersion else { return }
        persistTask?.cancel(); persistTask = nil
        commit(version)
    }
    func deleteSession(_ id: UUID) { onSessionInvalidation?(id); archive.sessions.removeAll { $0.id == id }; persist() }
    /// Phrases the learner kept, newest first. A notebook, never learning evidence.
    var savedPhrases: [SavedPhrase] { archive.phrases.filter { $0.languageID == language.id }.sorted { $0.savedAt > $1.savedAt } }
    func isPhraseSaved(_ text: String) -> Bool {
        let key = language.id + "|" + SavedPhrase.normalize(text)
        return archive.phrases.contains { $0.key == key }
    }
    /// Returns how many were new, so the interface can say what happened.
    @discardableResult func savePhrases(_ texts: [String], meaningLanguage: String, source: String) -> [SavedPhrase] {
        var kept = archive.phrases
        var added: [SavedPhrase] = []
        for text in texts {
            let phrase = SavedPhrase(languageID: language.id, text: text, meaningLanguage: meaningLanguage, source: source)
            guard !phrase.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !kept.contains(where: { $0.key == phrase.key }) else { continue }
            kept.append(phrase); added.append(phrase)
        }
        guard !added.isEmpty else { return [] }
        archive.savedPhrases = kept; persist()
        return added
    }
    func setPhraseMeaning(_ id: UUID, meaning: String) {
        guard let index = archive.phrases.firstIndex(where: { $0.id == id }) else { return }
        var kept = archive.phrases
        kept[index].meaning = String(meaning.prefix(300))
        archive.savedPhrases = kept; persist()
    }
    func deletePhrase(_ id: UUID) { archive.savedPhrases = archive.phrases.filter { $0.id != id }; persist() }
    func hideWord(_ id: String) { archive.preferences.hiddenWords.append(id); persist() }
    func correctPassage(sessionID: UUID, passageID: String, text: String) {
        guard let index = archive.sessions.firstIndex(where: { $0.id == sessionID }),
              let passage = archive.sessions[index].passages.first(where: { $0.id == passageID && $0.speaker == .user }) else { return }
        for (offset, fragment) in passage.fragments.enumerated() {
            archive.sessions[index].correctFragment(id: fragment.id, text: offset == 0 ? String(text.prefix(10_000)) : "")
        }
        onSessionInvalidation?(sessionID)
        persist()
    }
    func deleteAll() {
        if let migrationBackupURL {
            do { try FileManager.default.removeItem(at: migrationBackupURL) }
            catch CocoaError.fileNoSuchFile { /* Most installations have no migration backup. */ }
            catch {
                self.error = "Mural couldn’t delete the older learning backup. Your conversations are still here. Please try again."
                return
            }
        }
        archive.sessions.forEach { onSessionInvalidation?($0.id) }
        archive.sessions = []; archive.preferences.hiddenWords = []; archive.savedPhrases = nil; persist()
    }
    func exportData() throws -> Data { try archive.encoded() }
    func importData(_ data: Data) throws {
        let imported = try Archive.decode(data)
        archive = try archive.merging(imported)
        persist()
    }
    private static let saveFailure = "Mural couldn’t save your progress. Please export a backup and try again."
    private func persist() {
        persistTask?.cancel(); persistTask = nil
        version += 1
        commit(version)
    }
    private func schedulePersist() {
        version += 1
        guard persistTask == nil else { return }
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.persistTask = nil
            await self.commitCoalesced()
        }
    }
    /// Encodes off the main actor, so a long transcript does not spend the main thread on JSON
    /// while the conversation is running.
    private func commitCoalesced() async {
        let target = version
        guard target > writtenVersion else { return }
        let snapshot = archive
        guard let payload = await Task.detached(priority: .utility, operation: { try? snapshot.encoded(pretty: false) }).value else {
            self.error = Self.saveFailure; return
        }
        // A later write may have landed while this one was encoding.
        guard target > writtenVersion else { return }
        store(payload, version: target)
    }
    private func commit(_ target: Int) {
        guard let payload = try? archive.encoded(pretty: false) else { self.error = Self.saveFailure; return }
        store(payload, version: target)
    }
    private func store(_ payload: Data, version target: Int) {
        writtenVersion = max(writtenVersion, target)
        document.payload = payload
        do { try container.mainContext.save(); error = nil }
        catch { self.error = Self.saveFailure }
    }
}

enum CredentialStore {
    /// Each key has its own Keychain item under the same protections. The admin key reads
    /// billing only; it is never sent anywhere the project key is not.
    enum Slot: String { case project = "owner", admin = "admin" }
    private static let service = "no.william.mural.openai"
    private static func query(_ slot: Slot) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: slot.rawValue, kSecAttrSynchronizable as String: false]
    }
    static func read(_ slot: Slot = .project) -> String? {
        var q = query(slot); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static var hasKey: Bool { read() != nil }
    static var hasAdminKey: Bool { read(.admin) != nil }
    static func save(_ key: String, slot: Slot = .project) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = slot == .admin ? "sk-admin-" : "sk-"
        guard value.hasPrefix(prefix), value.count >= 20, !value.contains(where: \.isWhitespace) else { throw slot == .admin ? KeyError.invalidAdmin : KeyError.invalid }
        // A project key saved as the admin key, or the reverse, would be sent to the wrong kind of endpoint.
        if slot == .project, value.hasPrefix("sk-admin-") { throw KeyError.adminAsProject }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(slot) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(slot); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw KeyError.save }
        } else if status != errSecSuccess { throw KeyError.save }
    }
    static func delete(_ slot: Slot = .project) throws {
        let status = SecItemDelete(query(slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.remove }
    }
    enum KeyError: LocalizedError {
        case invalid, invalidAdmin, adminAsProject, save, remove
        var errorDescription: String? {
            switch self {
            case .invalid: "Enter a valid OpenAI API key."
            case .invalidAdmin: "Enter an OpenAI Admin key. Admin keys begin with sk-admin-."
            case .adminAsProject: "That is an Admin key. Use a project API key here; the Admin key belongs under Spending."
            case .save: "The key couldn’t be saved to this device’s Keychain."
            case .remove: "The key couldn’t be removed. Unlock this iPhone and try again."
            }
        }
    }
}
