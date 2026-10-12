import AppKit
import Charts
import NaturalInputCore
import SwiftUI

struct UsageStatsPane: View {
    static let chartDays = 30

    @ObservedObject var model = UsageStatsModel.shared
    @ObservedObject private var refresh = SettingsRefresh.shared
    @AppStorage(UsageStats.recordingDefaultsKey) private var recording = UsageStats.recordingDefault
    @Environment(\.colorScheme) private var scheme
    @State private var metric: StatsMetric = .characters
    @State private var heroPeriod: StatsPeriod = .today
    @State private var selectedDay: Date?
    @State private var copied = false

    var body: some View {
        let periods = StatsPeriod.allCases.map { UsageSummary(model.days, lastDays: $0.days, now: model.now) }
        let hero = periods[heroPeriod.index]
        let overview = UsageOverview(days: model.days, now: model.now)
        let series = UsageStatsLayout.dailySeries(model.days, count: Self.chartDays, now: model.now)
        Form {
            Section {
                StatsHero(summary: hero, period: heroPeriod, picker: $heroPeriod)
                HStack {
                    Spacer()
                    Button(copied ? "已拷貝" : "拷貝成圖片", systemImage: copied ? "checkmark" : "photo.on.rectangle") {
                        copyImage(summary: hero, series: series)
                    }
                    .controlSize(.small)
                    .help("把上面的成果與最近 \(Self.chartDays) 天長條圖拷貝成一張圖片（只有數字、不存檔），可以直接貼到訊息裡")
                }
            }
            Section {
                table(periods)
            } footer: {
                SettingsHelp(text: "「省下的打字時間」＝這些字用打的要多久（每分鐘打 \(Int(UsageStats.typingCharactersPerMinute)) 個字估算），"
                             + "扣掉實際花的說話與等字出現的時間；是估計，不是量測。"
                             + "「沒插進去」的文字仍在選單列的「最近口述」；「失敗」含轉錄失敗、逾時與沒有聲音；「取消」是按 Esc 或 ✕ 等沒有送出的。")
            }
            Section("連續使用") {
                StatsStreakRow(overview: overview)
            }
            Section("最近 \(Self.chartDays) 天") {
                Picker("顯示", selection: $metric) {
                    ForEach(StatsMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                StatsBarChart(series: series, metric: metric, selection: $selectedDay)
            }
            Section("最近 \(UsageHeatmap.defaultWeeks) 週") {
                StatsHeatmap(map: UsageHeatmap(days: model.days, now: model.now))
            }
            Section("資料") {
                Toggle("記錄使用統計", isOn: $recording)
                SettingsHelp(text: "關掉之後，新的口述就不會再記。已經記下的統計不會因此刪掉；要刪，請按下面的「刪除全部統計…」。")
                SettingsHelp(text: "只記數字（次數、字數、時間），不記你說了什麼。存在這台 Mac，保留 \(UsageStats.retentionDays) 天，不會送出。")
                HStack {
                    Spacer()
                    Button("刪除全部統計…") { model.confirmDeleteAll() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: scrollingPaneHeight)
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
        .onChange(of: refresh.generation) { model.reload() }
    }

    private func table(_ periods: [UsageSummary]) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 7) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(Array(StatsPeriod.allCases.enumerated()), id: \.offset) { i, p in
                    Text(p.columnTitle).font(.caption.weight(.semibold)).foregroundStyle(i == 0 ? .primary : .secondary)
                }
            }
            Divider()
            groupHeader("用量")
            row("口述", periods.map { $0.sentRounds > 0 ? "\($0.sentRounds) 次" : "–" })
            row("插入的字", periods.map { $0.charactersInserted > 0 ? "\($0.charactersInserted.formatted()) 字" : "–" })
            row("說話時間", periods.map { $0.recordingMillis > 0 ? Self.duration(millis: $0.recordingMillis) : "–" })
            row("估計省下的打字時間", periods.map { Self.saved(seconds: $0.savedSeconds) })
            Divider()
            groupHeader("品質")
            row("成功插入", periods.map { p in p.successPercent.map { "\(p.insertedRounds) 次（\($0)%）" } ?? "–" })
            row("講完到出字（中位數）", periods.map { Self.seconds($0.medianStopToFirstKeystrokeMillis) })
            row("沒插進去／失敗／取消", periods.map { p in
                p.notInsertedRounds + p.failedRounds + p.cancelledRounds > 0
                    ? "\(p.notInsertedRounds)／\(p.failedRounds)／\(p.cancelledRounds)" : "–" })
        }
        .monospacedDigit()
    }

    private func groupHeader(_ title: String) -> some View {
        GridRow {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
                .gridCellColumns(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, _ values: [String]) -> some View {
        GridRow {
            Text(title)
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                Text(v).fontWeight(i == 0 ? .semibold : .regular)
            }
        }
    }

    private func copyImage(summary: UsageSummary, series: [UsageDailyPoint]) {
        let card = StatsShareCard(summary: summary, period: heroPeriod, series: series, metric: metric)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    static func duration(millis: Int) -> String {
        let s = max(0, millis) / 1000
        if s >= 3600 { return "\(s / 3600) 小時 \(s % 3600 / 60) 分" }
        if s >= 60 { return "\(s / 60) 分" }
        return "\(s) 秒"
    }

    static func saved(seconds: Int) -> String {
        if seconds >= 3600 { return String(format: "約 %.1f 小時", Double(seconds) / 3600) }
        if seconds >= 60 { return "約 \(Int((Double(seconds) / 60).rounded())) 分鐘" }
        return seconds > 0 ? "不到 1 分鐘" : "–"
    }

    static func seconds(_ ms: Int?) -> String {
        guard let ms else { return "–" }
        return String(format: "%.1f 秒", Double(ms) / 1000)
    }
}

enum StatsMetric: String, CaseIterable {
    case characters, rounds
    var title: String { self == .characters ? "字數" : "次數" }
}

enum StatsPeriod: Int, CaseIterable {
    case today, week, month
    var days: Int { [1, 7, 30][rawValue] }
    var index: Int { rawValue }
    var pickerTitle: String { ["今天", "7 天", "30 天"][rawValue] }
    var columnTitle: String { ["今天", "最近 7 天", "最近 30 天"][rawValue] }
}

struct StatsHero: View {
    let summary: UsageSummary
    let period: StatsPeriod
    var picker: Binding<StatsPeriod>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(period.columnTitle).font(.callout.weight(.semibold)).foregroundStyle(StatsPalette.onHeroSecondary)
                Spacer()
                if let picker { StatsHeroPicker(selection: picker) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.charactersInserted > 0 ? summary.charactersInserted.formatted() : "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StatsPalette.onHero)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("字").font(.title3.weight(.semibold)).foregroundStyle(StatsPalette.onHeroSecondary)
            }
            if summary.savedSeconds > 0 {
                Label("約省下 \(UsageStatsPane.saved(seconds: summary.savedSeconds).replacingOccurrences(of: "約 ", with: ""))打字時間",
                      systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StatsPalette.onHero)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(StatsPalette.heroChip, in: .capsule)
            }
            Text(detailLine).font(.caption).foregroundStyle(StatsPalette.onHeroSecondary).monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatsPalette.heroGradient, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var detailLine: String {
        var parts: [String] = []
        if summary.sentRounds > 0 { parts.append("口述 \(summary.sentRounds) 次") }
        if summary.recordingMillis > 0 { parts.append("說話 \(UsageStatsPane.duration(millis: summary.recordingMillis))") }
        if let ms = summary.medianStopToFirstKeystrokeMillis { parts.append("講完到出字 \(UsageStatsPane.seconds(ms))") }
        return parts.isEmpty ? "這段期間還沒有口述" : parts.joined(separator: "・")
    }
}

struct StatsHeroPicker: View {
    @Binding var selection: StatsPeriod

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button { selection = p } label: {
                    Text(p.pickerTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .foregroundStyle(selection == p ? StatsPalette.heroSegmentSelectedText : StatsPalette.onHero)
                        .background(selection == p ? Color.white : Color.clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == p ? .isSelected : [])
            }
        }
        .padding(2)
        .background(StatsPalette.heroChip, in: .capsule)
    }
}

struct StatsStreakRow: View {
    let overview: UsageOverview

    var body: some View {
        HStack(spacing: 0) {
            column("活躍天數", overview.activeDays)
            Divider().frame(height: 32)
            column("目前連續", overview.currentStreak).padding(.leading, 14)
            Divider().frame(height: 32)
            column("最長連續", overview.longestStreak).padding(.leading, 14)
        }
    }

    private func column(_ title: String, _ days: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(days)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                Text("天").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatsBarChart: View {
    let series: [UsageDailyPoint]
    let metric: StatsMetric
    @Binding var selection: Date?

    private func value(_ p: UsageDailyPoint) -> Int { metric == .characters ? p.charactersInserted : p.sentRounds }

    private var selectedPoint: UsageDailyPoint? {
        guard let selection else { return nil }
        let cal = UsageStatsLayout.calendar()
        return series.first { cal.isDate($0.dayStart, inSameDayAs: selection) }
    }

    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, p in
                BarMark(x: .value("日期", p.dayStart, unit: .day), y: .value(metric.title, value(p)))
                    .foregroundStyle((UsageStatsLayout.calendar().isDateInToday(p.dayStart) ? StatsPalette.barToday : StatsPalette.bar)
                        .opacity(selectedPoint == nil || selectedPoint?.dayStart == p.dayStart ? 1 : 0.45))
            }
            if let p = selectedPoint {
                RuleMark(x: .value("日期", p.dayStart, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(p.dayStart.formatted(.dateTime.month(.defaultDigits).day()))　\(value(p).formatted()) \(metric == .characters ? "字" : "次")")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.regularMaterial, in: .rect(cornerRadius: 5))
                    }
            }
        }
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.25))
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .frame(height: 150)
        .accessibilityLabel("最近 \(series.count) 天每天的\(metric.title)")
    }
}

struct StatsHeatmap: View {
    let map: UsageHeatmap
    private let cell: CGFloat = 16
    private let gap: CGFloat = 4
    private static let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    Color.clear.frame(width: 14, height: 12)
                    ForEach(0..<7, id: \.self) { i in
                        Text(Self.weekdayLabels[i]).font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: 14, height: cell)
                    }
                }
                ForEach(Array(map.weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        Text(week.monthLabel.map { "\($0)月" } ?? " ")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: cell, height: 12, alignment: .leading)
                        ForEach(0..<7, id: \.self) { i in
                            square(level: week.days[i]?.level, empty: week.days[i] == nil)
                                .frame(width: cell, height: cell)
                                .help(week.days[i].map { "\($0.dayStart.formatted(.dateTime.month(.defaultDigits).day()))　\($0.characters.formatted()) 字" } ?? "")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: gap) {
                Spacer()
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach(0...UsageHeatmap.levels, id: \.self) { square(level: $0, empty: false).frame(width: 11, height: 11) }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 \(map.weeks.count) 週，有口述的日子 \(map.weeks.flatMap(\.days).filter { ($0?.level ?? 0) > 0 }.count) 天")
    }

    private func square(level: Int?, empty: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(empty ? Color.clear : Self.color(level: level ?? 0))
    }

    static func color(level: Int) -> Color { StatsPalette.heat(level: level) }
}

struct StatsShareCard: View {
    let summary: UsageSummary
    let period: StatsPeriod
    let series: [UsageDailyPoint]
    let metric: StatsMetric
    @State private var none: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsHero(summary: summary, period: period, picker: nil)
            Text("最近 \(series.count) 天的\(metric.title)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            StatsBarChart(series: series, metric: metric, selection: $none)
            Text("Talkiie").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 480)
        .background(StatsPalette.shareBackground)
    }
}
