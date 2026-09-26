import Foundation

/// One model's spend in one calendar month.
public struct MonthlySpend: Identifiable, Hashable, Sendable {
    public var month: Date
    public var model: String
    public var amount: Double
    public var id: String { "\(month.timeIntervalSince1970)-\(model)" }
    public init(month: Date, model: String, amount: Double) { self.month = month; self.model = model; self.amount = amount }
}

/// Monthly spend by model, from OpenAI's Costs API or from Mural's own session records.
public struct SpendReport: Sendable, Equatable {
    public var rows: [MonthlySpend]
    public init(rows: [MonthlySpend]) { self.rows = rows }

    public var months: [Date] { Array(Set(rows.map(\.month))).sorted() }
    /// Models ordered by total spend, largest first, so the legend and colours stay stable.
    public var models: [String] {
        var totals: [String: Double] = [:]
        for row in rows { totals[row.model, default: 0] += row.amount }
        let ordered = totals.sorted { (a: (key: String, value: Double), b: (key: String, value: Double)) -> Bool in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }
        return ordered.map(\.key)
    }
    public func total(in month: Date) -> Double { rows.filter { $0.month == month }.reduce(0) { $0 + $1.amount } }
    public func rows(in month: Date) -> [MonthlySpend] { rows.filter { $0.month == month }.sorted { $0.amount > $1.amount } }

    /// Keeps the `limit` largest models and folds the rest into one "Other" row per month, so a
    /// chart of a busy account stays readable.
    public func collapsed(keeping limit: Int) -> SpendReport {
        let kept = Set(models.prefix(limit))
        var merged: [Date: [String: Double]] = [:]
        for row in rows { merged[row.month, default: [:]][kept.contains(row.model) ? row.model : Self.other, default: 0] += row.amount }
        return Self.report(merged)
    }
    public static let other = "Other"

    /// Flattens month → model → amount into rows ordered by month, then model.
    private static func report(_ totals: [Date: [String: Double]]) -> SpendReport {
        var rows: [MonthlySpend] = []
        for (month, models) in totals {
            for (model, amount) in models { rows.append(MonthlySpend(month: month, model: model, amount: amount)) }
        }
        rows.sort { (a: MonthlySpend, b: MonthlySpend) -> Bool in a.month == b.month ? a.model < b.model : a.month < b.month }
        return SpendReport(rows: rows)
    }

    /// The model a Costs API line item bills, such as `gpt-realtime-2.1-mini` from
    /// `"gpt-realtime-2.1-mini-2026-08-28, audio input"`. A service prefix (`"evals | …"`) and a
    /// dated snapshot suffix are removed so every snapshot of a model is counted together. A line
    /// item with no model name is kept as written.
    public static func model(fromLineItem lineItem: String?) -> String {
        guard var text = lineItem?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "Unlabelled" }
        if let bar = text.range(of: " | ", options: .backwards) { text = String(text[bar.upperBound...]) }
        if let comma = text.range(of: ",") { text = String(text[..<comma.lowerBound]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if let snapshot = text.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) { text.removeSubrange(snapshot) }
        return text.isEmpty ? "Unlabelled" : text
    }

    /// Reads the `data` buckets of one or more Costs API pages. Buckets are daily; each result is
    /// placed in the calendar month its bucket starts in. `project` keeps only one project's costs
    /// when the results were grouped by project.
    public static func billed(pages: [[String: Any]], project: String? = nil, calendar: Calendar = .current) -> SpendReport {
        var totals: [Date: [String: Double]] = [:]
        for page in pages {
            for bucket in page["data"] as? [[String: Any]] ?? [] {
                guard let start = (bucket["start_time"] as? NSNumber)?.doubleValue,
                      let month = calendar.dateInterval(of: .month, for: Date(timeIntervalSince1970: start))?.start else { continue }
                for result in bucket["results"] as? [[String: Any]] ?? [] {
                    if let project, result["project_id"] as? String != project { continue }
                    let amount = result["amount"] as? [String: Any]
                    guard let value = (amount?["value"] as? NSNumber)?.doubleValue, value.isFinite, value != 0,
                          (amount?["currency"] as? String ?? "usd").lowercased() == "usd" else { continue }
                    totals[month, default: [:]][model(fromLineItem: result["line_item"] as? String), default: 0] += value
                }
            }
        }
        return report(totals)
    }

    /// Project IDs present in grouped Costs API pages, for choosing which project to show.
    public static func projects(in pages: [[String: Any]]) -> [String] {
        let ids = pages.flatMap { ($0["data"] as? [[String: Any]] ?? []).flatMap { ($0["results"] as? [[String: Any]] ?? []).compactMap { $0["project_id"] as? String } } }
        return Array(Set(ids)).sorted()
    }

    /// Mural's own estimate: each session's voice cost under the voice model it used, and its
    /// text requests under the text model, at list prices. It knows nothing of web-search charges
    /// or other apps on the same account.
    public static func estimated(sessions: [SessionRecord], calendar: Calendar = .current) -> SpendReport {
        var totals: [Date: [String: Double]] = [:]
        for session in sessions {
            guard let month = calendar.dateInterval(of: .month, for: session.startedAt)?.start else { continue }
            let voice = session.voiceModelID.flatMap(VoiceModel.init(rawValue:)) ?? .live
            let voiceCost = session.estimatedVoiceCost
            if voiceCost > 0 { totals[month, default: [:]][voice.rawValue, default: 0] += voiceCost }
            let textIn: Double = Double(max(0, session.inputTokens)) * VoicePricing.textInput
            let textOut: Double = Double(max(0, session.outputTokens)) * VoicePricing.textOutput
            let text: Double = (textIn + textOut) / 1_000_000
            if text > 0 { totals[month, default: [:]][VoicePricing.textModel, default: 0] += text }
        }
        return report(totals)
    }
}
