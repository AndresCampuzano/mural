# How Mural keeps languages independent

A learner can be comfortable in Korean and new to Japanese. Mural therefore gives each conversation an immutable language ID and projects vocabulary, challenge level and capability observations from that language's evidence only. Identical word forms have different vocabulary keys across languages, so hiding or recalling a word in one language does not affect another.

Language-specific content lives in `apps/ios/Core/Languages/`. Each module defines its greeting, regional speech guidance, writing conventions, lemma rules, six teaching stages and cultural theme overrides. `LanguageRegistry` supplies the available choices to the UI.

| Storage ID | Learning target | Locale |
| --- | --- | --- |
| `ko` | Korean as spoken in Seoul | `ko-KR` |
| `ja` | Standard Japanese | `ja-JP` |

These locales describe the initial teaching targets. Modules accept valid regional usage from learners. Regional pronunciation is a model instruction and still needs listening checks. The interface itself is English in every case; only the conversation, the themes and the optional reading aid change with the module.

`TeachingPolicy` combines a module with the shared teaching rules. Voice, assessment, typed replies, help, word lookup, subtitles and current-topic search all use that policy. The audio transport and provider connection remain shared. A module can override selected theme IDs while inheriting the common conversation catalog.

Switching is allowed between conversations. It clears the current screen context and invalidates pending language-dependent work. Previous messages and sourced topic briefs are selected only from the active language. Learner replies can use a support language; the meaning-subtitle language is a separate preference. Vocabulary senses remain in English to keep glossary identities stable.

Archive version 2 stores language IDs explicitly. Version 1 records migrate to `LanguageRegistry.defaultID`, and their hidden-word keys gain the same namespace as new evidence. The SwiftData record itself retains its original identity. Before persisting that migration, the app saves a protected copy of the original payload in its Application Support/Mural directory. The API key stays in Keychain. Backups with unknown language IDs or mixed-language topic attachments are rejected without replacing existing data.

## Word boundaries and reading help

Two module fields carry everything script-specific. `wordSegmentationLocale` names the locale used to find word boundaries in a script written without spaces; `nil` splits on whitespace. `readingAidName` labels an optional Latin reading shown under target text; `nil` hides the control.

Korean sets neither. Hangul is written with spaces, so whitespace splitting gives correct word links, and it sounds out letter by letter, so a romanization would be a crutch rather than help.

Japanese sets both. Without segmentation the whole sentence would become one link, so `Readings` runs the system word tokenizer with `ja_JP` and links コーヒー, 飲み and ます separately. The same pass takes each token's Latin transcription, which is a *kana-faithful* reading: it spells out what is written. That is right for sounding out kana and wrong in a few well-known places, so a small table overrides the particles は, を and へ with their spoken wa, o and e, and the two fixed greetings こんにちは and こんばんは. What remains is still an aid, not a pronunciation guide — 私 transcribes as watakushi rather than watashi, 日本 as nippon rather than nihon, and long vowels appear as written (benkyou) rather than with macrons. Kanji with more than one reading and pitch accent both need a listening check.

The reading appears separately below selectable target text with a Show/Hide control. Lemmas stay in the original script, observed forms and quotations stay unchanged, and a generated reading never becomes learning evidence.

These are compiled modules. Adding one ships with an app update; there is no remote module download or extra service. Every new language needs a proficient-speaker teaching and pronunciation review.

See [how to add a language](add-language.md) for the implementation steps.

## Golden fixtures

Fixtures under `shared/fixtures/cross-platform/` pin core behavior that is easy to change by accident: the JSON backup archive's required fields and round-trip, the learner projection derived from a recorded conversation, and the spoken-language redirect decisions. `swift test` reads them directly, so a change to storage or redirect logic fails a test rather than a device.

A backup is compared semantically, not byte-for-byte. Swift's `JSONEncoder` sorts keys when writing an archive, so archives are checked by decoding and re-validating, never by comparing raw bytes.
