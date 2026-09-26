import XCTest
@testable import MuralCore

final class SpendingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func result(_ value: Double, _ lineItem: String?, project: String? = nil, currency: String = "usd") -> [String: Any] {
        let amount: [String: Any] = ["value": value, "currency": currency]
        return ["object": "organization.costs.result", "amount": amount, "line_item": lineItem as Any, "project_id": project as Any]
    }
    private func bucket(_ day: Date, _ results: [[String: Any]]) -> [String: Any] {
        ["object": "bucket", "start_time": day.timeIntervalSince1970, "results": results]
    }

    func testALineItemNamesItsModelWithoutSnapshotServiceOrCostType() {
        XCTAssertEqual(SpendReport.model(fromLineItem: "gpt-realtime-2.1-mini-2026-08-28, audio input"), "gpt-realtime-2.1-mini")
        XCTAssertEqual(SpendReport.model(fromLineItem: "gpt-live-1, voice session"), "gpt-live-1")
        XCTAssertEqual(SpendReport.model(fromLineItem: "evals | gpt-4o-mini-2024-07-18, input"), "gpt-4o-mini")
        XCTAssertEqual(SpendReport.model(fromLineItem: "web search tool calls"), "web search tool calls")
        XCTAssertEqual(SpendReport.model(fromLineItem: nil), "Unlabelled")
        XCTAssertEqual(SpendReport.model(fromLineItem: "  "), "Unlabelled")
    }

    func testBilledCostsAreSummedByCalendarMonthAndModelAcrossPages() {
        let first: [String: Any] = ["data": [
            bucket(date(2026, 8, 30), [result(1.25, "gpt-live-1, voice"), result(0.10, "gpt-5.6-luna, input")]),
            bucket(date(2026, 9, 1), [result(0.50, "gpt-live-1, voice"), result(0.20, "gpt-realtime-2.1-mini-2026-08-28, audio output")])
        ]]
        let second: [String: Any] = ["data": [
            bucket(date(2026, 9, 2), [result(0.30, "gpt-realtime-2.1-mini, audio input"), result(0, "gpt-5.6-luna, input"),
                                      result(9, "gpt-live-1, voice", currency: "eur")])
        ]]
        let report = SpendReport.billed(pages: [first, second], calendar: calendar)
        let august = calendar.dateInterval(of: .month, for: date(2026, 8, 15))!.start
        let september = calendar.dateInterval(of: .month, for: date(2026, 9, 15))!.start
        XCTAssertEqual(report.months, [august, september])
        XCTAssertEqual(report.total(in: august), 1.35, accuracy: 1e-9)
        XCTAssertEqual(report.total(in: september), 1.00, accuracy: 1e-9)
        let mini = report.rows(in: september).first { $0.model == "gpt-realtime-2.1-mini" }
        XCTAssertEqual(mini?.amount ?? 0, 0.50, accuracy: 1e-9)
        // Zero rows and other currencies are not counted.
        XCTAssertFalse(report.rows(in: september).contains { $0.model == "gpt-5.6-luna" })
        XCTAssertEqual(report.models.first, "gpt-live-1")
    }

    func testAProjectFilterKeepsOnlyThatProjectsCosts() {
        let page: [String: Any] = ["data": [bucket(date(2026, 9, 3), [result(2, "gpt-live-1, voice", project: "proj_mural"),
                                                                       result(5, "gpt-5.6-luna, input", project: "proj_other")])]]
        XCTAssertEqual(SpendReport.projects(in: [page]), ["proj_mural", "proj_other"])
        let mural = SpendReport.billed(pages: [page], project: "proj_mural", calendar: calendar)
        XCTAssertEqual(mural.rows.map(\.model), ["gpt-live-1"])
        XCTAssertEqual(SpendReport.billed(pages: [page], calendar: calendar).rows.count, 2)
    }

    func testMalformedPagesAreIgnoredRatherThanCounted() {
        let broken: [String: Any] = ["data": [["start_time": "soon"], ["results": [result(4, "gpt-live-1")]], "nonsense"]]
        XCTAssertTrue(SpendReport.billed(pages: [broken, [:]], calendar: calendar).rows.isEmpty)
    }

    func testTheEstimateSplitsVoiceByTheModelEachSessionUsedAndAddsText() {
        var live = SessionRecord(languageID: "ko"); live.startedAt = date(2026, 9, 4); live.voiceSeconds = 600
        var mini = SessionRecord(languageID: "ja"); mini.startedAt = date(2026, 9, 5)
        mini.voiceModelID = "gpt-realtime-2.1-mini"; mini.voiceCost = 0.12
        mini.inputTokens = 1_000_000; mini.outputTokens = 1_000_000
        var old = SessionRecord(languageID: "ko"); old.startedAt = date(2026, 7, 1); old.voiceSeconds = 60
        let report = SpendReport.estimated(sessions: [live, mini, old], calendar: calendar)
        let september = calendar.dateInterval(of: .month, for: date(2026, 9, 15))!.start
        let rows = report.rows(in: september)
        XCTAssertEqual(rows.first { $0.model == VoicePricing.liveModel }?.amount ?? 0, 0.50, accuracy: 1e-9)
        XCTAssertEqual(rows.first { $0.model == "gpt-realtime-2.1-mini" }?.amount ?? 0, 0.12, accuracy: 1e-9)
        let text: Double = VoicePricing.textInput + VoicePricing.textOutput
        XCTAssertEqual(rows.first { $0.model == VoicePricing.textModel }?.amount ?? 0, text, accuracy: 1e-9)
        XCTAssertEqual(report.months.count, 2)
    }

    func testCollapsingKeepsTheLargestModelsAndFoldsTheRestIntoOther() {
        let month = date(2026, 9, 1)
        let rows: [MonthlySpend] = [MonthlySpend(month: month, model: "a", amount: 5), MonthlySpend(month: month, model: "b", amount: 3),
                                    MonthlySpend(month: month, model: "c", amount: 1), MonthlySpend(month: month, model: "d", amount: 0.5)]
        let collapsed = SpendReport(rows: rows).collapsed(keeping: 2)
        XCTAssertEqual(Set(collapsed.rows.map(\.model)), ["a", "b", SpendReport.other])
        XCTAssertEqual(collapsed.rows.first { $0.model == SpendReport.other }?.amount ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(collapsed.total(in: month), 9.5, accuracy: 1e-9)
    }
}
