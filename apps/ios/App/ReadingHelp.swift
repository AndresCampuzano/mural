import SwiftUI
import MuralCore

/// Keeps target text selectable and word links intact, with an optional reading below it.
/// A language whose script maps to sound directly, such as Hangul, supplies no reading
/// aid and this view renders nothing.
struct ReadingHelp: View {
    let text: String
    let language: LanguageModule
    @State private var expanded = true

    var body: some View {
        if let name = language.readingAidName, let locale = language.wordSegmentationLocale,
           let reading = Readings.reading(text, locale: locale) {
            VStack(spacing: 6) {
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Hide \(name)" : "Show \(name)", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        // A caption-sized label collapses to a hairline target between the
                        // chevron and the title. Pad it out and give it an explicit shape so
                        // the whole control accepts a tap.
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("reading-toggle")
                if expanded {
                    Text(reading).font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("reading-text")
                }
            }.foregroundStyle(MuralColor.secondary)
        }
    }
}
