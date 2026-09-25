# Build verification

11 September 2026

- iOS simulator build succeeded with Xcode 26.4.1.
- The signed device build succeeded and was installed on the connected iPhone 16 Pro running iOS 26.6.1. The app bundle passed strict code-signature verification.
- After the owner trusted the developer profile, Mural launched successfully on the iPhone at 22:00 CEST.
- 18 learning-policy tests passed: duplicate events and word proposals, late transcript fragments, overlapping speakers, exact transcript concatenation, supported and typed production, English input, evidence provenance, transcript corrections, recall spacing and decay, archive integrity, and source URL validation.
- 3 native UI tests passed on an iPhone 16 Pro simulator running iOS 26.4: greeting and subtitle toggle; secure key settings; theme persistence across Talk and Words.
- The Talk screen was inspected from a simulator capture. The initial clipped toolbar wordmark and crowded footer were corrected.
- WebRTC is pinned to 152.0.0 with the package checksum verified by Swift Package Manager. License notices are bundled in the app.

The owner entered an API key and confirmed live speech playback, but reported that speech through the iPhone was too quiet. Cellular connectivity, pronunciation and teaching quality still need the pilot below.

## Speaker-volume correction

Mural originally set the speaker preference directly on the active audio session. WebRTC then applied its own default configuration when its audio unit started, removing that preference. The fix sets `defaultToSpeaker` in `RTCAudioSessionConfiguration` before creating the connection. This follows [WebRTC's configuration mechanism](https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/components/audio/RTCAudioSession.mm) and [Apple's speaker routing option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker), which preserves connected headset routes.

The fix also balances app-owned audio activation and deactivation. Calling cleanup before the first connection or after an already-closed connection no longer decrements WebRTC's activation count.

- Signed device build passed and the update was installed.
- All 3 native UI regression tests passed.
- An explicit debug-only `--verify-audio` run tests two real Live connections using the device's saved key. It uses an in-memory learning store and writes only connection, route, volume and cleanup results to `Documents/audio-verification.json`. It incurs API usage and is never part of automatic offline tests.
- A real Live session received both speech and transcript. During playback, the output route was `Speaker`, the system volume was 100%, and the speaker preference remained set. Audio was released after closure. The owner confirmed: “Yes, the volume is good now”.
- The first repeat test muted input before the greeting was complete. Its second connection opened and closed correctly but had no caption during the 12-second observation window. The test now keeps input running, as required by [OpenAI's greeting flow](https://developers.openai.com/api/docs/guides/live-conversations#greet-before-the-caller-speaks).
- The corrected test build was installed. Its repeat run could not start because the phone had locked again. The speaker fix is confirmed by the first live playback and the owner's listening check; the corrected two-greeting test remains unverified.

## Personal pilot

Use the phone on cellular, with the Mac disconnected. Confirm:

1. Start requests microphone permission, connects and greets in Norwegian.
2. English replies produce Norwegian speech, with optional meaning subtitles.
3. A meaningful error receives a gentle correction without breaking the exchange.
4. Mute prevents microphone audio reaching the conversation; End releases the connection.
5. A theme persists when opening Words, and saved progress survives relaunch.
6. Current-topic lookup displays sources and declines to invent facts when unavailable.
7. Backgrounding, calls, a network drop and the session time limit close or recover clearly.
8. Speaker and AirPods audio are intelligible and yield promptly to interruption.

Record incorrect corrections, misheard speech, English leakage and unsupported claims. The recall thresholds and model judgments remain provisional until this pilot provides enough evidence to refine them.

## Spanish and language modules

Spanish targets the Spain variety. Language modules now supply the greeting, pronunciation and writing guidance, grammar focus, lemma rules and cultural themes. Shared prompts cover voice, subtitles, teaching, help, typed replies, lookup and sourced topics.

- 28 core tests passed, including version-1 migration, bilingual archive round trips, language-specific vocabulary and challenge levels, hidden cognates, source-language validation, topic-language consistency and Spanish prompt isolation.
- All 4 native UI tests passed. The language-switch test selects Spanish, checks its greeting and themes, opens Spanish Words, and switches back to Norwegian.
- The signed iPhone build passed and was installed over the existing app.
- A protected pre-migration learning payload is retained in Application Support/Mural/before-language-modules.json inside the app container. It contains no API key.
- Both Spanish live checks passed on the iPhone using its saved key. Each received speech and captions through the `Speaker` route at 100% system volume, retained the speaker preference and released audio after closing. Non-content results are in `spanish-live-verification.json`.
- Mural was relaunched normally with the persistent learning store after testing.

The first UI attempt ran a stale simulator test runner. Removing only that generated runner loaded the new tests; a later text assertion was corrected to account for uppercase section labels. The final suite passed with no failures.

## Conversation reset and Meaning

Ended conversations return to the ready screen after 15 seconds, or immediately through **New conversation**. This clears the current dialogue and theme while preserving preferences, saved conversations and learning progress. A transcript opened before the reset retains its content.

Meaning previously required an active session, so tapping it after ending could do nothing. Its label also sat outside the button's hit area. Streaming transcript fragments repeatedly cancelled translation requests, and cancelled requests could overwrite newer UI state. The new translation controller coalesces incoming fragments, validates request generations, retains a usable translation during updates, separates caches by subtitle language and exposes errors with an explicit retry.

- 35 core tests passed. Seven new tests cover continuous speech, coalescing, late cancelled responses, corrected transcripts, passage changes, retry behavior and subtitle-language changes.
- All 7 native UI tests passed. New checks tap the Meaning label after ending, verify immediate reset and retained history, wait for the actual 15-second reset, and keep a transcript open across that reset.
- The signed build succeeded and was installed over the existing iPhone app.
- A live Spanish session verified an English translation while active, immediate cached Meaning after ending, a new French translation requested after ending, automatic reset after 15 seconds, retained session history and released audio. Every check passed. The report is in `meaning-live-verification.json`; it contains no key, transcript or audio.
- The explicit debug invocation `--verify-audio --verify-meaning --verify-language=es` uses an in-memory learning store and the device's saved API key. It incurs API usage and is not run by the offline suite. Mural was reopened normally afterward with its persistent store.

The live test verifies that translations arrive and the controls respond. It does not establish translation accuracy across extended conversations or all supported subtitle languages.

## English, French, onboarding and AI consent

12 September 2026

The English module requests broadly intelligible pronunciation and accepts regional variants in its teaching policy. French targets France and accepts valid Francophone variants. Both modules have six teaching-focus levels, lemma guidance, cultural themes and a spoken fallback for unavailable lookups. Shared prompts now treat English as a possible learning language, and the speech-language check follows the selected target.

The welcome flow has two screens: learning language, then subtitle language. Greetings cycle across the installed languages, with a static alternative when Reduce Motion is enabled. The final screen identifies OpenAI as the processor, explains the audio and text transfer, links the privacy policy and requires **Agree and continue**.

Consent is recorded as a versioned preference. Older archives without a consent version keep their prior language choices and require agreement. Before the next live session, an existing user can agree in one consent sheet or choose **Not now** and continue reading saved material. Word lookup, current-topic search and meaning translation also check consent before making a provider request. New onboarding records the same consent version. The privacy-policy URL is `https://mural.chat/privacy/`; public availability depends on deploying the website.

- **41 core tests passed**, including separate progress across four languages, English as target-language evidence, French accents and elisions, language recovery, and old-archive consent decoding.
- **All 11 native UI tests passed** on the iPhone 16 Pro simulator running iOS 26.4. The suite covers target/subtitle selection, an explicit subtitle choice surviving Back, English and French settings, existing-user consent decline/accept/no-repeat, the Advanced API-key disclosure, and the prior conversation/Meaning regressions.
- The completed UI result is `Test-Mural-2026.09.12_13-37-03-+0200.xcresult`, ending at 13:40 CEST. The two failures in the earlier 13:06 run were accessibility-selector issues: the privacy link's element type and an identifier inherited from the key disclosure. Both were corrected and passed in this full run.
- The welcome screens were captured from native UI tests for visual review. After reducing the subtitle step's decorative header to leave room for the example and consent footer, its targeted onboarding test passed again at 13:45 CEST in `Test-Mural-2026.09.12_13-45-06-+0200.xcresult`. That targeted check also compiled the then-current combined app source; it did not exercise the account flows.
- UI fixtures use in-memory records. Preview starts do not connect to OpenAI. No API key was added, replaced or removed by these tests.

These results cover the language modules, onboarding, consent and existing conversation controls. They do not verify the separate account or billing work. English and French live pronunciation and teaching quality still need listening checks; the earlier Spanish speaker and Meaning results above remain historical evidence for their tested builds.

## Native account foundation

12 September 2026

The source now includes Google sign-in through the system authentication browser with OAuth authorization code and PKCE S256, native Sign in with Apple, a separate Keychain record for Mural sessions, and the server's challenge, exchange, wallet, sign-out and deletion contracts. The Settings destination is hidden unless explicit deployment and provider configuration passes the account gate. The default app remains BYOK and does not offer hosted trial minutes or purchases.

- **48 core tests passed** in the combined source, including seven new account tests. The new checks cover HTTPS configuration and provider capability gates, the RFC 7636 S256 test vector, raw nonce binding, callback origin/state/duplicate-parameter rejection, form encoding, expiry and backend scoping, exact wallet arithmetic and cancelled-operation invalidation.
- The combined iOS Simulator build passed at 13:45 CEST, including the account view and conditional Settings link.
- The unsigned **0.1.0 (1)** Release archive was refreshed successfully at 13:46 CEST with the final onboarding, consent and account source. It includes both privacy manifests and third-party notices. This is a build artifact, not a distribution-signed upload.
- The seven new account source, test and documentation files were scanned for secret-shaped keys, signing material, private local paths and device identifiers; no matches were found. Fixtures use synthetic values. Google's button artwork is the unmodified provider asset with its source and branding notice recorded.

No Google or Apple account was signed in, no provider credentials were configured, and no live Mural account or payment was created during this verification. Keychain persistence, configured provider callbacks and Apple authorization revocation still require device checks against the deployed server. See [managed-account setup](../docs/managed-accounts.md) for configuration and the remaining checks.

## Permanent release links

12 September 2026

Settings now has a **Help and privacy** section with `https://mural.chat/privacy/`, `https://mural.chat/terms/` and `https://mural.chat/support/`. Existing onboarding, consent and disabled-account links already used the intended privacy and terms URLs.

- A source check confirmed all seven native release-link occurrences use HTTPS, the intended domain and the canonical paths, without query strings or fragments.
- The combined simulator build and the existing Settings navigation test passed at 14:42 CEST. This checked the secure-key disclosure and return to Talk; it did not browse the release pages.
- The unsigned **0.1.0 (1)** archive was refreshed at 14:44 CEST with the Settings links. Compilation and archive creation are not Apple upload validation, TestFlight review or App Store approval.
- Custom-domain availability remained pending at this checkpoint. Confirm all three pages load without login after DNS propagation before submitting the app.


## 12 September 2026 — silent final assessment and access requests

The final native update passed 53 Core tests, including five final-assessment lifecycle tests, and five focused simulator UI checks. New-user language/subtitle onboarding, AI consent, existing-user consent, Settings, meanings after ending and reset remained available. Closing attempts the latest unassessed user passage silently for up to 15 seconds. Results apply to the original saved transcript; reset or a new conversation does not redirect them, and deletion or correction cancels stale work. App termination can interrupt this in-memory attempt. The signed personal update was installed and launched on the authorized iPhone without uninstalling or changing saved preferences. No new live AI conversation was used for this check.

The backend passed 57 tests in Node 22 with PostgreSQL 17 and no skipped tests. Access-request cases cover validation, exact origins, proxy identity, concurrency, duplicates, admission limits, retention, private export and deletion. A separate real Stripe sandbox Checkout test received signed payment and refund webhooks: one payment credited $10 once, duplicate delivery added no credit, and the full sandbox refund restored a zero balance with one reversal. A fresh session verified that Adaptive Pricing is disabled and the amount remains USD 12.16. No real money, production customer records or live payment credentials were used. These checks do not validate a native purchase flow or enable production payments.

## Optional Google signup and Settings cleanup

12 September 2026, 16:35 CEST checkpoint

Google and Apple configuration are now independent. The ignored local build configuration enables Mural's public Google iOS client for `no.william.mural` and `https://api.mural.chat`. Checked-in defaults remain disabled. Apple stays disabled while Hackmamba Inc.'s developer enrollment is processing; optional entitlement and compilation settings are prepared for an eligible profile.

The account screen shows a terms agreement and privacy acknowledgment before sign-in, states that learning history stays on the phone, and explains that BYOK does not require an account. After login it requests the account profile, validates its ID against the Mural session, and displays the provider and verified email when available. Wallet requests and balances are absent from this screen. Account creation does not enable hosted voice, trial minutes or purchases.

- **56 Core tests passed** at 16:25 CEST. Three new tests cover Google without Apple capability, Apple-only configuration and invalid Google starts, plus account-profile identity, provider, timestamp and email validation. The prior final-assessment, language and account security tests also passed.
- **Three focused native UI tests passed** at 16:26 CEST: account-free language/subtitle onboarding, secure API-key Settings and retained license notices after removing the WebRTC explanation and external license link. Result: `Test-Mural-2026.09.12_16-25-19-+0200.xcresult`.
- With Google configured, **two focused UI tests passed** at 16:34 CEST in `Test-Mural-2026.09.12_16-33-55-+0200.xcresult`. The Settings test entered Account, checked the Google button and agreement, then returned to secure API-key entry. The second test confirmed bundled notices remain accessible. Visual review confirmed Apple is absent and the screen fits without a storage error.
- The initial unsigned simulator account capture exposed a Keychain error in preview mode. Preview launches now skip account credential loading and block sign-in requests. Real signed builds retain secure storage and actionable error reporting. The final UI run includes this correction.
- The signed iPhone build passed with the existing personal team and bundle ID. Its processed Info.plist was checked for the intended Google client, callback, API origin and disabled Apple provider. `git diff --check` passed.

At this checkpoint, the configured Google build had not been installed and no real Google login, account creation, persistence, sign-out or deletion had been verified. The UI runs used preview mode and did not contact an identity provider. Apple authorization and revocation also remain unverified. These results establish native build and layout readiness, not a completed live account flow.

At 16:48:47 CEST, the signed Google-configured update was installed over the existing app and launched normally on the authorized iPhone. The personal signing identity and `no.william.mural` bundle were preserved; no uninstall, learning-data changes, onboarding reset or credential inspection was performed. The user was directed to **Settings → Account → Sign in with Google**. Actual Google authorization and the resulting account profile remain pending confirmation.

Later on 12 September, the owner confirmed that Google sign-in worked on that installed build. This is a user-confirmed live authorization result; no bearer token, Google credential or OpenAI key was inspected. Relaunch persistence, cancellation, sign-out, expiry and account deletion remain unverified on the physical phone. Apple sign-in and revocation remain pending.

## Native security review

12 September 2026

The review covered tracked native source and fixtures: Keychain services, OAuth PKCE/state/callback handling, session scope, fixed API destinations and redirects, ATS settings, source links, diagnostics, backup import/export and the pinned WebRTC package. It found and corrected these issues:

- The file importer read the entire selected file before enforcing the 30 MB archive limit. It now checks file size and uses a bounded read that also rejects growth beyond the limit.
- Imported durations, usage counters and revision numbers could exceed the range used by the interface. Extreme values passed the old decoder and could later trap during integer conversion or addition. Regression tests first reproduced acceptance, then passed after validation was added. Date values are now bounded too.
- Separately valid imports could produce a combined archive beyond the size or session limits accepted on relaunch. Import now validates the complete candidate before replacing local history. Duplicate sessions stay unchanged, local preferences and AI consent stay local, and invalid learning evidence is removed.
- Removing the OpenAI key ignored the Keychain result and always changed the UI to report removal. It now reports success only for a successful deletion or an already-absent item, and keeps the existing state when removal fails.

**60 Core tests passed** at 17:17 CEST, including four new backup-security tests and both merged byte/session limits. The synthetic numeric-import test failed with three acceptance errors before the fix. **Two focused native UI tests passed** at 17:14 CEST for Settings/account/API-key navigation and account-free language onboarding. The completed result is `Test-Mural-2026.09.12_17-13-31-+0200.xcresult`. No real account, API key or learning backup was used by these tests.

The tracked-file credential-pattern scan found no usable embedded key. Its only private-key marker was an intentionally invalid server test fixture. The reviewed network paths use HTTPS and reject redirects for credential-bearing requests; ATS has no transport exceptions. No app WebView or app code that logs credentials was found. Source links accept HTTPS without user-info, and the word-lookup link handler is confined to the caption view.

WebRTC remains pinned to 152.0.0 and package revision `1d04692697cb642bfebf6ad2dd99fe52649c3d6d`. The package's binary checksum matches the publisher's [M152 release metadata](https://github.com/stasel/WebRTC/releases/tag/152.0.0). This is dependency provenance verification, not a source or binary audit of WebRTC. The project describes separate [security tracking for standalone clients](https://webrtc.github.io/webrtc-org/bugs/security/).

This was a bounded source review with synthetic regression tests, not a penetration test, exhaustive fuzzing, traffic interception or device Keychain inspection. Physical-device Keychain failure handling, sign-out/deletion and the new backup paths still need device checks. The fixes had not been installed at this checkpoint. The review also flagged account email/user-ID privacy declarations for the separate release-preparation work.

The signed security update subsequently built successfully and was installed over the existing iPhone app at approximately 17:21 CEST, using the same personal team and `no.william.mural` bundle. No uninstall, learning-data change, credential inspection, sign-in action or AI request was performed. The normal launch attempt at 17:21:04 was denied by iOS because the phone was locked (`FBSOpenApplicationErrorDomain` code 7, `Locked`). Installation is verified; opening and checking this updated build on the phone remains pending unlock.

## German, Italian, Brazilian Portuguese and Mandarin

13 September 2026

The owner selected Brazilian Portuguese and Simplified Chinese with pinyin help. The new modules use stable IDs `de`, `it`, `pt` and `zh`, with locales `de-DE`, `it-IT`, `pt-BR` and `zh-CN`. They add greetings, six teaching stages, regional speech and writing guidance, lemma rules, cultural themes and target-language lookup fallbacks. The four existing learning languages remain registered.

Mandarin builds on Richard Guerre's [contribution in #4](https://github.com/Chuloo/mural/pull/4). Review found that per-character transliteration gives incorrect readings for common words such as 银行 and 音乐, and that replacing the caption/transcript with noninteractive ruby text removes lookup and copying. The adapted implementation uses system word readings and separate optional pinyin below the original text, preserving Chinese word links and selectable transcripts. It also accepts Chinese script IDs in speech-language detection and keeps generated pinyin out of vocabulary identities and evidence. The contribution's global simulator architecture exclusion was not needed; the existing project generator and documented arm64 build settings were retained.

- **70 core tests passed** at 16:19 CEST. The new coverage includes all eight languages in one archive, per-language selection after decoding, hidden cognates, native characters and accents, assisted/typed evidence, rejection of foreign-language evidence, prompt paths, Chinese script detection, polyphonic word readings, ü normalization and word boundaries. The first run exposed three pinyin expectations involving Apple's combining-mark `v` notation; normalization now operates on Unicode scalars and those regressions pass.
- **20 native UI tests passed** at 16:30 CEST on the iPhone 16 Pro simulator. The full suite covers the four new onboarding choices, all language settings, themes and vocabulary headings, returning to Norwegian, Simplified Chinese meanings, pinyin visibility, retained Mandarin transcripts, the largest accessibility text size, consent, secure-key Settings and existing reset/Meaning behavior. Result: `.build/FourLanguages-UI-Final.xcresult`. The initial run had three test-selector failures: two partially obscured onboarding rows and duplicate pinyin labels behind a presented transcript. Scrolling whole rows into view and scoping the text lookup resolved them; the complete rerun passed.
- **79 backend tests passed with no skips**, using Node 23.4.0 and an isolated temporary PostgreSQL 15 database. The database was stopped afterward. The added local HTTP test verifies all eight locale codes and regional provider prompts, and rejects unsupported codes before making a provider request. TypeScript compilation passed. The backend language additions are source changes; no hosted-service deployment was performed.
- The **signed Debug iPhone build and unsigned Release build passed**. The Release executable excludes the live language-verification helper. The signed app was installed over the existing personal installation with the same bundle ID and signing configuration.
- **All four live device checks passed** on the owner's iPhone 16 Pro running iOS 26.6.1. Each check opened one real voice session, received a greeting and speaker audio, sent a beginner request in English and a more complex typed request in the target language, detected target-language output, obtained English meanings and a word lookup, retained cached meaning after ending, released audio, decoded its exported temporary archive, and switched away and back with separate progress. Each produced supported evidence without independent recall credit. Mandarin also produced pinyin. Content-free reports are retained locally as `verification/language-live-de.json`, `language-live-it.json`, `language-live-pt.json` and `language-live-zh.json`.
- The live checks used `--verify-audio --verify-language-flow --verify-language=<ID>`, the key already saved inside the app and in-memory learning records. The microphone was muted after connection. No key or account credential was read out of the app, and no audio or transcript was exported. Mural was relaunched without test arguments at 16:28:54 CEST, and its normal process was confirmed running with the persistent store.

Visual review after the full UI run found that the fixed consent footer crowded the screen at the largest accessibility text size. Consent now scrolls with the content at those sizes, the Continue button stays at the bottom, the Back icon keeps a usable size, and changing onboarding steps resets the scroll position. Three focused tests passed at 16:35 CEST in `.build/FourLanguages-Accessibility-Fresh.xcresult`, including German selection, standard consent onboarding and the largest-text Mandarin flow. A fourth check at 16:36 CEST confirmed that Back preserves an explicit subtitle choice, in `.build/FourLanguages-Onboarding-Back.xcresult`. The corrected screenshot shows readable consent and an unobscured Continue button. A preceding targeted run used a stale unsigned simulator test runner; replacing only that runner and using a fresh build directory resolved the mismatch. The signed Debug and unsigned Release builds passed again after the layout correction. The final signed app was installed at 16:36 CEST; its immediate normal launch was blocked because the phone had locked, and the owner was asked to unlock it.

After the owner unlocked the phone, the final build launched normally at 16:37:51 CEST. Its running process was confirmed. This reopened the persistent learning store without verification arguments.

The device results verify the application/provider paths with synthetic typed input and real voice output. They do not verify recognition of a human speaker, pronunciation, tones, correction quality, unscripted interruptions, headphones or cellular operation. The proficient-speaker checks requested in issues #10–#13 remain open. Pinyin uses dictionary tones and may need correction for names, ambiguous words and connected-speech tone changes.

## Korean and Japanese only

17 September 2026

At the owner's request the other eight language modules were removed. Mural now teaches Korean (`ko`, `ko-KR`) and Japanese (`ja`, `ja-JP`) through an English interface. `LanguageRegistry.defaultID` is `ko`, so a first launch and a version-1 archive migration both adopt Korean instead of the removed Norwegian module. An archive naming any removed module is rejected as `unsupportedLanguage` rather than crashing the force-unwrapped module lookup.

Script handling moved out of the Mandarin-specific helper into two module fields. `wordSegmentationLocale` gives Japanese `ja_JP` word boundaries; without it the whole sentence becomes a single lookup link, because Japanese is written without spaces. Korean sets neither field: Hangul is written with spaces and sounds out letter by letter. `readingAidName` offers Japanese romaji taken from the system dictionary transcription.

That transcription spells kana as written, which is wrong for the particles は, を and へ and for the greetings こんにちは and こんばんは. A five-entry table overrides those. What remains is a sounding-out aid, not a pronunciation guide: 私 transcribes as watakushi rather than watashi, 日本 as nippon rather than nihon, and long vowels appear as written (benkyou) rather than with macrons. Kanji with more than one reading and pitch accent both still need a listening check. No proficient-speaker review of either module's teaching, correction or pronunciation quality has been done.

- **73 core tests passed.** Coverage includes the two-module registry, per-language progress and glossary keys, rejection of the other language's evidence for every evidence kind, version-1 migration onto the default module, rejection of an archive from a removed module, prompt isolation between Korean and Japanese, Japanese word segmentation and romaji with its particle overrides, Korean whitespace word links, and redirect decisions for regional and script identifiers.
- **17 native UI tests passed** on an iPhone 17 simulator running iOS 26.2. They cover both onboarding choices, the reading aid appearing for Japanese and staying absent for Korean, hiding and showing romaji, settings language switching with themes and vocabulary headings, the Japanese transcript keeping its source text and romaji through a reset, Simplified Chinese meanings, the largest accessibility text size, consent, secure-key settings and the existing reset/Meaning behaviour.
- **The iOS app target built** for the simulator after regenerating the Xcode project for the renamed reading-aid view.
- **The API service type-checked and its locale test passed.** Its hosted-voice language map now offers only `ko-KR` and `ja-JP` and rejects everything else before making a provider request. This is a source change; no hosted service was deployed, and hosted voice remains disabled.

One interface defect was found and fixed during these runs. The reading aid's Show/Hide control never responded to a tap: a caption-sized `Label` inside a plain button collapsed to a hairline target between its chevron and title, so the tap landed on nothing. Padding the label and giving it an explicit content shape fixed it, confirmed by the previously failing test. An intermediate attempt to persist the choice in `UserDefaults` was reverted because the stored value leaked between test runs; the control is view-local state again.

Not verified: no live device check was run for either module, so nothing here establishes real speech recognition, pronunciation, correction quality or teaching effectiveness for Korean or Japanese. The marketing and App Store screenshot sets still need recapturing for anything beyond the Korean sample content.

## Level and speaking pace

18 September 2026

The learner now chooses how much of the conversation is carried in the language they already
read, and how quickly Mural speaks. `GuidanceLevel` offers **Starting out** (Mural speaks the
chosen subtitle language and teaches one short target phrase at a time), **Finding my feet**
(target language leading, a few words of support when something is new) and **In at the deep
end** (target language only). An absent or unrecognised stored value falls back to the deep
end, so existing installs and existing backups behave exactly as before. The choice is made on
a new middle onboarding step and in Settings; a running conversation adopts a new level at
once.

`SpeechPace` maps Slow, Gentle, Natural and Brisk onto 0.7, 0.85, 1.0 and 1.15 and sends the
value as `session.audio.output.speed` when the session is created. The provider documents the
range as 0.25–1.5 with a default of 1.0, allows the value to change only between model turns,
and applies it to the generated audio rather than to how the model composes speech, so
`TeachingPolicy` asks for matching pacing in words as well and a new pace waits for the next
conversation. An unset pace follows the level, so Starting out begins slow.

Both settings are language-agnostic. Every prompt takes a `LanguageModule`, and the level, its
description and its pace read identically for Korean and Japanese.

The level changes prompts only. `LearningEngine.validate` never receives it, and its existing
downgrade still applies: a beginner repeating a phrase Mural has just said is recorded as
assisted, with no independent recall and no recall bar.

- **87 core tests passed**, including the 14 new level and pace tests: the fallback for an
  archive written before the setting existed, an unknown level falling back instead of
  rejecting a backup, a stored speed outside the provider range being rejected, every pace
  inside the documented range, the deep-end prompts being byte-identical to the previous
  target-only prompts, the beginner and intermediate prompts for both modules, prompt
  isolation between Korean and Japanese at every level, and assisted-not-independent credit in
  both modules.
- **18 native UI tests passed** on an iPhone 17 simulator running iOS 27.0, in
  `.build/Guidance-UI.xcresult`. They cover the three-step onboarding for both languages, the
  level defaulting to Starting out with its pace line, moving back through both steps while
  keeping an explicit subtitle choice, the largest accessibility text size, and the Settings
  level and pace pickers including the level description following a switch to Japanese.
- **The signed device build passed and was installed** over the existing personal installation
  on the owner's iPhone 15 Pro Max, using the same bundle identifier and signing team.
- One interface defect was found and fixed during the run. At the largest accessibility text
  size three described level rows could not be scrolled clear of the fixed Continue footer, so
  the test could never reach the first row. At accessibility sizes the rows now show their
  title only and the selected level's description moves below the list.

Not verified: no live conversation was held, so nothing here establishes that the provider
accepts the speed field in practice, how the beginner level actually sounds, or whether the
taught phrases are well chosen. The hosted voice service in `services/api` was not changed and
still sends no speed; it remains disabled. No proficient speaker has reviewed either module's
teaching at any level.

### HTTP 400 on the first live conversation

The owner hit `HTTP 400` starting voice on the build above. The prime suspect is the
`session.audio.output.speed` field: the range and semantics were read from OpenAI's realtime
documentation, but this app creates sessions at `/v1/live/sessions` with `gpt-live-1`, and
nothing had ever verified that this surface accepts the field. The build also discarded the
provider's explanation, so the failure showed only a bare status.

Two changes, neither of which assumes the cause:

- `APIClient` now reads `error.message` and `error.param` from a rejection body, bounded to 300
  characters, and shows them in the alert. The request, which carries the Authorization header,
  is never included.
- `LiveTransport` creates the session with the pace field, and on a `400` retries once without
  it. A rejected create is never billed and opens no session, so the retry is safe, and a pace
  the model will not accept can no longer cost the conversation. The conversation then reports
  that it is speaking at normal speed, with the provider's reason.

87 core tests and 18 native UI tests passed after the change, and both builds succeeded; the
corrected build was installed. The UI suite does not reach this code, because a preview launch
never opens a session. Whether the field is the cause, and whether the pace works at all
against this model, is still unverified — the next live attempt decides it.

## Saved phrases

18 September 2026

When Mural uses target-language phrases in a line — "for goodbye you say X, for hello Y" — the
Talk screen now offers one capsule per phrase under the caption, plus **Save all** when there
is more than one. Kept phrases are read in **Words → Saved phrases**, the target text first
with its meaning underneath, and are removed by swiping.

A phone caption leaves very little room, so the chooser is a single horizontally scrolling row:
each capsule holds its phrase on one line with middle truncation, the row costs one line of
height however much Mural said, and the kept phrases are read on their own screen rather than
on top of the conversation. At accessibility text sizes the capsules take the full width and
the row scrolls instead of wrapping.

The list is a notebook, not evidence. `LearningEngine` never reads it, saving grants no recall
bar, and the list says so in its own footer. Saving is immediate and local; meanings are
fetched afterwards in one batched request, and only when the learner saves or asks for them, so
opening the list spends nothing. A phrase whose meaning never arrived reads "No meaning yet"
and offers to fetch it rather than claiming to be loading.

Phrases are found by script: each module declares `scriptRanges`, so a mixed line separates
cleanly. A space between two target words belongs to the phrase and a space before the
learner's own language does not; quotation marks and sentence punctuation are trimmed;
repeats are offered once; the list is capped at six.

- **100 core tests passed**, including 13 new ones: every module declaring its own script and
  finding its own greeting, the two-phrase explanation in both Korean and Japanese, spacing
  inside a phrase against spacing beside English, trimmed quotes and sentence endings, one
  module's script never being offered to the other, deduplication and the six-phrase cap,
  truncation at 200 characters, archives without the list still decoding, round trips in both
  modules, rejection of an empty phrase and of an unregistered language, import adding only
  phrases the device lacks, and a saved phrase producing no learner evidence at all.
- **20 native UI tests passed** on an iPhone 17 simulator running iOS 27.0, in
  `.build/Phrases-UI.xcresult`, including the two new ones: saving a Korean phrase from the
  caption, seeing it in the saved list with "No meaning yet" and the offer to fetch meanings,
  removing it back to the empty state; and the same capture in Japanese, where the saved phrase
  also carries its romaji.
- `shared/fixtures/cross-platform/archive.json` now pins a saved phrase, so the field round
  trips across platforms.

One test assertion was dropped as unsound rather than made to pass: after removing a phrase it
checked the capsule on the Talk screen again, but the conversation resets itself fifteen seconds
after ending, so the caption — and its capsules — are legitimately gone by then. Removal is
proved by the empty state instead.

Not verified: no live conversation has produced these phrases yet. The extraction is exercised
against fixed strings and the seeded preview conversation, not against real speech transcripts,
and the batched meaning request has never run against the provider. Whether the phrases Mural
actually teaches are the ones worth keeping is unknown, and no proficient speaker has reviewed
the meanings.

## Long conversations heating the phone

The complaint was that after a few minutes of talking the iPhone becomes hot and the interface
slows down. Four things in the running conversation grew with the length of the transcript or
ran far more often than they needed to.

**The whole archive was re-encoded on the main thread on every save.** `LearningStore.persist`
JSON-encoded every session ever recorded, pretty-printed and with sorted keys, and the running
conversation called it through `scheduleSave` roughly every 750 ms. The cost grew with the
transcript and with the learner's whole history, which is why it got worse the longer the app
had been used. Conversation-rate saves are now coalesced, encoded compactly and encoded off the
main actor; everything else — preferences, phrases, deletion, import — still writes at once.
`flush()` makes a coalesced write durable when a conversation ends and when the app leaves the
foreground, so the crash-loss window is a fraction of a second of transcript rather than
nothing at all, and the version counter drops a write that a newer one has already overtaken.

**The talk screen regrouped the entire transcript several times per frame.** `assistantPassage`,
`userPassage`, `caption` and `capturablePhrases` each rebuilt every passage from every fragment,
and audio levels arriving ten times a second invalidated the whole view. They are derived once
per transcript change now, and the orb and status line — the only parts that follow the audio
levels — read them in their own view, so a level change redraws the orb instead of the screen.

**The language-drift check ran `NLLanguageRecognizer` on every transcript delta.** It only
recorded the line once it had redirected, so a line that was not drifting was re-detected
several times a second over text that had barely changed. The first check for a line is
unchanged; a re-check now waits for the line to grow by 120 characters.

**Appending a fragment regrouped every passage.** `SessionRecord.append` called
`invalidateChangedAssessments`, which is linear in the whole conversation, for each of the
several deltas arriving per second. Only a user passage ever carries an assessment and passages
group per speaker, so an assistant fragment cannot invalidate one; that case and the
no-assessments case now skip the rebuild.

WebRTC statistics are also polled every 200 ms rather than every 100 ms, and a level that has
settled is not republished, so silence stops redrawing the orb.

- **102 core tests passed** (`swift test --package-path apps/ios`), including two new ones:
  Mural's own speech never invalidating the learner's recorded evidence while the learner
  speaking into the same passage still does, asserted for every registered module; and the
  compact device encoding and the readable export decoding to the same record.
- **20 native UI tests passed** on an iPhone 17 simulator running iOS 27.0, in
  `.build/Heat-UI.xcresult`, unchanged from before: the orb and status line moving into their
  own view leaves the talk screen, the caption, the phrase capsules and the transcript reading
  exactly as they did. No test was added for the changes themselves.
- The app builds for the simulator and for an iPhone 15 Pro Max, and is installed on it.

Not verified: **no measurement.** Nothing here was profiled — not with Instruments, not with a
thermal state reading, not with a before-and-after battery or CPU figure. The four changes were
chosen by reading the hot paths, and every one of them is a real reduction in work per second,
but whether they are enough to stop the phone getting hot is unknown until a long conversation
is run on the device. The orb itself was left alone: it renders a mesh gradient, three blurs, a
shadow and a mask at 30 fps whenever the Talk tab is open, including when no conversation is
running, and that constant cost is untouched and unmeasured.

## Reaching the saved phrases

The kept phrases were read through a button at the very bottom of the Words tab, below the word
list, the recall-bar legend, the footnotes and the capabilities panel. Nothing announced it and
you had to scroll past everything else to find it.

They are now a **tab of their own**, beside Talk, Themes and Words. That is one tap from
anywhere, including mid-conversation, and it also says something the old placement contradicted:
a recall bar is earned by retrieving a word in conversation and a kept phrase is only a
bookmark, so the two lists are different in kind and no longer sit one inside the other. The tab
opens with the same `PageHeading` the other tabs use, and keeps the swipe-to-remove, the
confirmation and the "Find the missing meanings" row. The buried button is gone; **Past
conversations** stays on Words.

Saving a phrase used to print "Saved to your phrases." and stop there. The confirmation is now a
capsule with a chevron that opens the tab, so the way in is offered at the moment the phrase
matters.

The orb gives up room once a conversation is running — 220pt to 150pt, and 170pt to 120pt at
accessibility text sizes — and returns to full size when the conversation ends. The phrase
capsules, which shared a phone's width side by side and truncated the middle of every phrase as
soon as Mural offered more than one, are now one full-width row each, stacked, each wrapping
rather than eliding. The two changes are the same change: the orb yields the room the rows need.

- **102 core tests passed.** No core behaviour changed; this is interface only.
- **21 native UI tests passed** on an iPhone 17 simulator running iOS 27.0, in
  `.build/Phrases-Tab-UI.xcresult`, including one new one: a phrase kept from the caption is
  reachable through the Phrases tab from Themes, Words and Talk in turn, and the old
  `saved-phrases` button is gone from Words while **Past conversations** remains. The Korean
  phrase test now goes through the confirmation capsule rather than through Words, and the
  Japanese one through the tab.

Two mistakes were made and corrected, both of which would have shipped silently:

- The notice's destination was first carried by a `didSet` on `notice`. `@Observable` leaves a
  property carrying an observer untracked, so notices would have stopped reaching the screen at
  all. It is a computed property over its own storage instead.
- `.accessibilityIdentifier` was left on the phrase rows' `VStack` after it stopped being a
  `ScrollView`. An accessibility modifier on a bare stack collapses it into a single element and
  the rows stopped being offered as separate buttons — invisible on screen, but the three phrase
  UI tests failed on it and VoiceOver would have lost them. The identifier was unused and is
  gone.

Not verified: the stacked rows have only been seen against the seeded preview line, which offers
one phrase. How a real conversation's six candidates look on a small phone, and whether the
smaller orb still reads as the thing you are talking to, have not been checked beyond a hands-on
pass on a physical iPhone.

## Practising by textbook unit

A module can now carry a `Course`: units as sections, and topics that each list the units they
draw on, so one topic appears under several units. Korean carries units 1–16 of Seoul National
University Korean 1A–1B, taken from the scope-and-sequence tables of the 1A student book and the
1B workbook (unit titles, vocabulary areas, grammar). The situations and topic words are Mural's
own; no dialogue or exercise from the books is reproduced. Japanese has no course and its Themes
tab is unchanged. Each topic runs as a role-play or as quick questions aimed at its grammar; each
unit also offers a drill over all of its grammar. A course topic becomes an ordinary
`ConversationTheme`, so `LearningEngine` never sees the course and practice earns recall bars
exactly as any conversation does.

- **109 core tests passed**, including seven new `CourseTests` that loop over every module with
  a course: every unit has a topic, every topic's units exist, a shared topic is listed under
  each of its units, both modes' prompts carry each target pattern and never another module's
  name, and "earlier grammar" reaches only backwards.
- **2 native UI tests passed** on an iPhone 17 simulator (`.build/course-ui.xcresult`): the new
  course test and the existing Themes/language-switch test. The full UI suite was not re-run.
  The new test caught a real bug: after switching language, the Themes tab stayed on the Korean
  unit screen. The tab's navigation now resets when the language changes.
- Built and installed on a physical iPhone 15 Pro Max. No live conversation was held on it.

Not verified: whether the model actually steers learners into the target grammar, and whether
the drills feel like practice rather than a quiz. The 1B student book was not scanned (only the
workbook), and the 1A text came from OCR of a phone scan, so the unit tables were read by eye
against it.

## A different opening each time

Every conversation used to open the same way: at the starting-out level Mural always taught the
greeting first, because both the session prompt's opening rule and the spoken opener named it,
and neither knew the chosen theme. The opener now carries the chosen theme's situation (or, with
no theme, asks Mural to pick and vary an everyday subject), and the app picks one of six opening
angles at random for each session. The greeting is offered as an example rather than a script,
and a greeting lesson is only asked for when the situation is about meeting someone.

- **110 core tests passed**, including a new one that loops over every module, every level and
  several themes and course topics: the opener contains the theme's situation, each angle gives a
  distinct prompt, no opener tells Mural to teach the greeting, and none names another module.
- Built and installed on the physical iPhone. Not verified: that the live model actually varies
  its first line in practice; that needs a few real conversations.
