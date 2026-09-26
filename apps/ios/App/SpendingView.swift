import SwiftUI
import Charts
import MuralCore

/// Monthly spend by model: billed by OpenAI when an Admin key is present, and Mural's own
/// estimate from this iPhone's conversations either way.
struct SpendingView: View {
    let coordinator: ConversationCoordinator
    enum Source: String, CaseIterable, Identifiable {
        case billed = "Billed by OpenAI", estimated = "Estimated here"
        var id: String { rawValue }
    }
    @State private var source: Source = CredentialStore.hasAdminKey ? .billed : .estimated
    @State private var hasAdminKey = CredentialStore.hasAdminKey
    @State private var pages: [[String: Any]] = []
    @State private var projectNames: [String: String] = [:]
    @State private var project: String?
    @State private var loading = false
    @State private var fetchedAt: Date?
    @State private var error: String?
    @State private var selectedMonth: Date?
    @State private var adminKey = ""
    @State private var keyMessage: String?

    private static let monthsShown = 6
    private static let palette: [Color] = [MuralColor.orange, Color(red: 0.52, green: 0.42, blue: 0.78),
                                           Color(red: 0.36, green: 0.58, blue: 0.40), Color(red: 0.86, green: 0.66, blue: 0.18),
                                           MuralColor.secondary]
    private var calendar: Calendar { .current }
    private var firstMonth: Date {
        let now = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return calendar.date(byAdding: .month, value: -(Self.monthsShown - 1), to: now) ?? now
    }
    private var thisMonth: Date { calendar.dateInterval(of: .month, for: .now)?.start ?? .now }

    private var fullReport: SpendReport {
        switch source {
        case .billed: SpendReport.billed(pages: pages, project: project, calendar: calendar)
        case .estimated: SpendReport.estimated(sessions: coordinator.store.sessions, calendar: calendar)
        }
    }
    private var report: SpendReport {
        SpendReport(rows: fullReport.rows.filter { $0.month >= firstMonth }).collapsed(keeping: Self.palette.count - 1)
    }
    private var focusMonth: Date { selectedMonth.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? thisMonth }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Spending", title: "Where it goes.", subtitle: "Monthly cost by model, over the last six months.")
                Picker("Source", selection: $source) { ForEach(Source.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("spending-source")
                if source == .billed && !hasAdminKey {
                    adminKeyCard
                } else {
                    if source == .billed { billedControls }
                    headline
                    chart
                    breakdown
                    Text(source == .billed
                         ? "Figures come from OpenAI’s Costs API for the whole organisation unless a project is chosen, and can lag behind the latest conversations. Your OpenAI dashboard is authoritative."
                         : "Mural’s own estimate from this iPhone’s conversations, at list prices as of \(VoicePricing.asOf). It leaves out web-search charges and anything used outside this app.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                    if source == .billed { adminKeyManagement }
                }
            }.padding(24)
        }
        .foregroundStyle(MuralColor.ink).background { MuralColor.cream.ignoresSafeArea() }
        .navigationTitle("Spending").navigationBarTitleDisplayMode(.inline)
        .task(id: source) { if source == .billed, hasAdminKey, pages.isEmpty { await load() } }
        .refreshable { if source == .billed { await load() } }
    }

    // MARK: Summary

    private var headline: some View {
        let current = report.total(in: thisMonth)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let previous = report.total(in: previousMonth)
        return VStack(alignment: .leading, spacing: 6) {
            Text("This month").font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(MuralColor.secondary)
            Text(Self.money(current)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("spending-this-month")
            // A month in progress is not compared as a percentage against a finished one, which
            // would always look like a saving.
            if previous > 0 {
                Text("Last month: \(Self.money(previous))").font(.footnote).foregroundStyle(MuralColor.secondary)
            } else if current == 0 {
                Text(loading ? "Fetching your costs…" : "Nothing recorded this month yet.").font(.footnote).foregroundStyle(MuralColor.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.peach.opacity(0.75), in: RoundedRectangle(cornerRadius: 26))
    }

    private var chart: some View {
        let models = report.models
        return VStack(alignment: .leading, spacing: 10) {
            if report.rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar").font(.system(size: 30, weight: .light)).foregroundStyle(MuralColor.secondary)
                    Text(loading ? "Fetching your costs…" : "No spending in the last six months.").font(.subheadline).foregroundStyle(MuralColor.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160)
            } else {
            Chart(report.rows) { row in
                BarMark(x: .value("Month", row.month, unit: .month), y: .value("Spend", row.amount))
                    .foregroundStyle(by: .value("Model", Self.name(row.model)))
                    .cornerRadius(4)
                    .opacity(calendar.isDate(row.month, equalTo: focusMonth, toGranularity: .month) ? 1 : 0.55)
            }
            .chartForegroundStyleScale(domain: models.map(Self.name), range: Array(Self.palette.prefix(max(1, models.count))))
            .chartXScale(domain: firstMonth...(calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth))
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true) } }
            .chartYAxis { AxisMarks { value in AxisGridLine(); AxisValueLabel { if let v = value.as(Double.self) { Text(Self.money(v, compact: true)) } } } }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartXSelection(value: $selectedMonth)
            .frame(height: 230)
            .accessibilityIdentifier("spending-chart")
            Text("Tap a month to see its breakdown.").font(.caption2).foregroundStyle(MuralColor.secondary)
            }
        }.padding(18).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))
    }

    private var breakdown: some View {
        let rows = report.rows(in: focusMonth)
        let total = max(report.total(in: focusMonth), 0.000_001)
        let models = report.models
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(focusMonth.formatted(.dateTime.month(.wide).year())).font(.system(.headline, design: .rounded))
                Spacer()
                Text(Self.money(report.total(in: focusMonth))).font(.system(.headline, design: .rounded)).monospacedDigit()
            }
            if rows.isEmpty { Text("No spending this month.").font(.subheadline).foregroundStyle(MuralColor.secondary) }
            ForEach(rows) { row in
                let color = Self.palette[min(Self.palette.count - 1, models.firstIndex(of: row.model) ?? Self.palette.count - 1)]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(Self.name(row.model)).font(.subheadline)
                        Spacer()
                        Text(Self.money(row.amount)).font(.subheadline).monospacedDigit()
                    }
                    GeometryReader { geometry in
                        Capsule().fill(color.opacity(0.18))
                            .overlay(alignment: .leading) { Capsule().fill(color).frame(width: geometry.size.width * row.amount / total) }
                    }.frame(height: 6)
                    Text("\(Int((row.amount / total * 100).rounded()))% of the month").font(.caption2).foregroundStyle(MuralColor.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("spending-row")
            }
        }.padding(18).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Billed data

    private var billedControls: some View {
        HStack(spacing: 12) {
            let projects = SpendReport.projects(in: pages)
            if projects.count > 1 {
                Picker("Project", selection: $project) {
                    Text("All projects").tag(String?.none)
                    ForEach(projects, id: \.self) { Text(projectNames[$0] ?? $0).tag(String?.some($0)) }
                }.pickerStyle(.menu).accessibilityIdentifier("spending-project")
            }
            Spacer()
            if loading { ProgressView() }
            else if let fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(MuralColor.secondary)
            }
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").padding(8).contentShape(Rectangle()) }
                .disabled(loading).accessibilityLabel("Refresh billed costs")
        }.overlay(alignment: .bottomLeading) {
            if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.orange).offset(y: 28) }
        }.padding(.bottom, error == nil ? 0 : 28)
    }

    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let fetched = try await coordinator.api.costPages(since: firstMonth)
            pages = fetched; fetchedAt = .now
            if projectNames.isEmpty { projectNames = await coordinator.api.projectNames() }
        } catch is CancellationError {
        } catch APIClient.APIError.http(let status, let detail) where status == 401 || status == 403 {
            error = "OpenAI didn’t accept the Admin key for billing (HTTP \(status)). Check that it can read usage." + (detail.map { " OpenAI said: \($0)" } ?? "")
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Admin key

    private var adminKeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 30, weight: .light))
            Text("See what OpenAI actually billed").font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Your usual key can talk to OpenAI but cannot read billing. OpenAI only shows costs to an Admin key. Create one with read-only permission, and paste it here on this iPhone.")
                .font(.subheadline).foregroundStyle(MuralColor.secondary)
            Link("Open OpenAI Admin keys", destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!).font(.subheadline)
            adminKeyField
            Text("It stays in this iPhone’s Keychain, never syncs or leaves in a backup, and is sent only to api.openai.com to read costs. Until then, “Estimated here” shows Mural’s own figures.")
                .font(.footnote).foregroundStyle(MuralColor.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(MuralColor.sage, in: RoundedRectangle(cornerRadius: 26))
            // A container, so the field and button inside stay separate accessibility elements.
            .accessibilityElement(children: .contain).accessibilityIdentifier("spending-admin-card")
    }

    private var adminKeyField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(hasAdminKey ? "Replace Admin key" : "OpenAI Admin key", text: $adminKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("admin-key")
            Button(hasAdminKey ? "Save replacement" : "Save Admin key") {
                do {
                    try CredentialStore.save(adminKey, slot: .admin)
                    adminKey = ""; hasAdminKey = true; keyMessage = nil; pages = []
                    Task { await load() }
                } catch { keyMessage = error.localizedDescription }
            }.disabled(adminKey.isEmpty).font(.headline).padding(.vertical, 12).padding(.horizontal, 18)
                .background(MuralColor.orange, in: Capsule()).contentShape(Capsule())
                .accessibilityIdentifier("save-admin-key")
            if let keyMessage { Text(keyMessage).font(.footnote).foregroundStyle(MuralColor.secondary) }
        }
    }

    private var adminKeyManagement: some View {
        DisclosureGroup("Admin key") {
            VStack(alignment: .leading, spacing: 12) {
                adminKeyField
                Button("Remove Admin key", role: .destructive) {
                    do {
                        try CredentialStore.delete(.admin)
                        hasAdminKey = false; pages = []; projectNames = [:]; project = nil; fetchedAt = nil
                    } catch { keyMessage = error.localizedDescription }
                }.font(.subheadline)
            }.padding(.top, 10)
        }.font(.subheadline).tint(MuralColor.ink)
    }

    // MARK: Formatting

    static func name(_ model: String) -> String {
        if let voice = VoiceModel(rawValue: model) { return voice.title }
        switch model {
        case VoicePricing.textModel: return "GPT-5.6 luna · text"
        case VoiceModel.learnerTranscriptionModel: return "Transcription"
        default: return model
        }
    }
    static func money(_ value: Double, compact: Bool = false) -> String {
        if compact && value >= 10 { return value.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(value > 0 && value < 0.1 ? 3 : 2)))
    }
}
