import SwiftUI
import ServiceManagement

struct ContentView: View {
    @ObservedObject var monitor: DiskMonitor
    @State private var launchAtLogin = false
    @State private var loginItemError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("対象: \(monitor.path)")
            Text("空き容量: \(monitor.freeText)")
            Text("空き率: \(monitor.freePercentText)")
            Text("今日の増減: \(monitor.todayDeltaText)")
            Text("1週間の増減: \(monitor.weekDeltaText)")
            Text("1ヶ月の増減: \(monitor.monthDeltaText)")
            Divider()

            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        loginItemError = error.localizedDescription
                    }
                }

            if !loginItemError.isEmpty {
                Text("エラー: \(loginItemError)")
                    .font(.caption)
            }

            Divider()

            Button("今すぐ更新") {
                monitor.refresh()
            }

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}

import Foundation
import Combine

final class DiskMonitor: ObservableObject {
    @Published var menuTitle: String = "-- (--%)"
    @Published var freeText: String = "-"
    @Published var freePercentText: String = "-"
    @Published var todayDeltaText: String = "-"
    @Published var weekDeltaText: String = "-"
    @Published var monthDeltaText: String = "-"

    let path: String
    private var timer: Timer?
    private let historyStore = DailyFreeSpaceHistoryStore()

    init(path: String) {
        self.path = path
        refresh(recordDailySnapshot: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh(recordDailySnapshot: Bool = false) {
        let url = URL(fileURLWithPath: path)

        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])

            guard
                let total = values.volumeTotalCapacity,
                let available = values.volumeAvailableCapacity
            else {
                menuTitle = "N/A"
                freeText = "取得失敗"
                freePercentText = "取得失敗"
                return
            }

            let total64 = Int64(total)
            let available64 = Int64(available)
            let freePercent = total64 > 0
                ? (Double(available64) / Double(total64)) * 100.0
                : 0.0

            let freeCapacityText = formatCapacity(available64)
            freeText = freeCapacityText
            freePercentText = String(format: "%.0f%%", freePercent)
            menuTitle = "\(freeCapacityText) (\(Int(freePercent))%)"

            if recordDailySnapshot {
                historyStore.recordTodayIfNeeded(bytes: available64)
            }
            updateDeltaTexts(currentAvailable: available64)
        } catch {
            menuTitle = "ERR"
            freeText = "取得エラー"
            freePercentText = error.localizedDescription
            todayDeltaText = "-"
            weekDeltaText = "-"
            monthDeltaText = "-"
        }
    }

    private func updateDeltaTexts(currentAvailable: Int64) {
        todayDeltaText = formattedDelta(from: historyStore.bytesForToday(), current: currentAvailable)
        weekDeltaText = formattedDelta(from: historyStore.bytes(daysBeforeToday: 7), current: currentAvailable)
        monthDeltaText = formattedDelta(from: historyStore.bytes(monthsBeforeToday: 1), current: currentAvailable)
    }

    private func formattedDelta(from baseline: Int64?, current: Int64) -> String {
        guard let baseline else {
            return "-"
        }

        let delta = current - baseline
        if delta == 0 {
            return "0 GB"
        }

        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(formatCapacity(abs(delta)))"
    }

    private func formatCapacity(_ bytes: Int64) -> String {
        let oneGB: Int64 = 1_000_000_000
        let oneTB: Int64 = 1_000_000_000_000

        if bytes >= oneTB {
            let terabytesTimes100 = (bytes * 100) / oneTB
            let wholePart = terabytesTimes100 / 100
            let fractionalPart = terabytesTimes100 % 100
            return String(format: "%lld.%02lld TB", wholePart, fractionalPart)
        }

        return "\(bytes / oneGB) GB"
    }
}

private final class DailyFreeSpaceHistoryStore {
    private let defaults: UserDefaults
    private let defaultsKey = "dailyFreeSpaceHistory.v1"
    private var calendar: Calendar

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 60 * 60)!
        self.calendar = calendar
    }

    func recordTodayIfNeeded(bytes: Int64, now: Date = Date()) {
        let key = dateKey(for: now)
        var history = loadHistory()
        guard history[key] == nil else {
            return
        }

        history[key] = bytes
        saveHistory(history)
    }

    func bytesForToday(now: Date = Date()) -> Int64? {
        loadHistory()[dateKey(for: now)]
    }

    func bytes(daysBeforeToday days: Int, now: Date = Date()) -> Int64? {
        guard let date = calendar.date(byAdding: .day, value: -days, to: now) else {
            return nil
        }

        return loadHistory()[dateKey(for: date)]
    }

    func bytes(monthsBeforeToday months: Int, now: Date = Date()) -> Int64? {
        guard let date = calendar.date(byAdding: .month, value: -months, to: now) else {
            return nil
        }

        return loadHistory()[dateKey(for: date)]
    }

    private func loadHistory() -> [String: Int64] {
        guard let data = defaults.data(forKey: defaultsKey),
              let history = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return [:]
        }

        return history
    }

    private func saveHistory(_ history: [String: Int64]) {
        guard let data = try? JSONEncoder().encode(history) else {
            return
        }

        defaults.set(data, forKey: defaultsKey)
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
