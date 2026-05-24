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

            Text("バージョン: \(appVersionText)")

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

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let version, !version.isEmpty else {
            return "-"
        }

        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }

        return version
    }
}

import Foundation
import Combine
import Darwin

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

    func refresh(recordDailySnapshot: Bool = true) {
        let url = URL(fileURLWithPath: path)

        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])

            guard
                let total = values.volumeTotalCapacity,
                let available = values.volumeAvailableCapacity.map(Int64.init) ?? statfsAvailableCapacity(path: path)
            else {
                menuTitle = "N/A"
                freeText = "取得失敗"
                freePercentText = "取得失敗"
                return
            }

            let total64 = Int64(total)
            let available64 = max(0, min(estimatedSystemSettingsAvailableCapacity(total: total64, rawAvailable: available), total64))
            let freePercent = total64 > 0
                ? (Double(available64) / Double(total64)) * 100.0
                : 0.0

            let freeCapacityText = formatCapacity(available64)
            freeText = freeCapacityText
            freePercentText = String(format: "%.0f%%", freePercent)
            menuTitle = "\(freeCapacityText) (\(String(format: "%.0f", freePercent))%)"

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
        weekDeltaText = formattedDelta(from: historyStore.bytes(onOrBeforeDaysBeforeToday: 7), current: currentAvailable)
        monthDeltaText = formattedDelta(from: historyStore.bytes(onOrBeforeMonthsBeforeToday: 1), current: currentAvailable)
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
            return String(format: "%.2f TB", Double(bytes) / Double(oneTB))
        }

        return String(format: "%.2f GB", Double(bytes) / Double(oneGB))
    }
}

private func statfsAvailableCapacity(path: String) -> Int64? {
    var stats = statfs()
    guard statfs(path, &stats) == 0 else {
        return nil
    }

    return Int64(stats.f_bavail) * Int64(stats.f_bsize)
}

private func estimatedSystemSettingsAvailableCapacity(total: Int64, rawAvailable: Int64) -> Int64 {
    guard
        let dataUsed = volumeSpaceUsed(path: "/System/Volumes/Data"),
        let cachedCategorySize = storageSettingsCachedCategorySize()
    else {
        return rawAvailable
    }

    let visibleUsed = max(0, dataUsed - cachedCategorySize)
    let estimatedAvailable = total - visibleUsed
    return max(rawAvailable, estimatedAvailable)
}

private func volumeSpaceUsed(path: String) -> Int64? {
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attributes.volattr = attrgroup_t(UInt32(ATTR_VOL_INFO) | UInt32(ATTR_VOL_SPACEUSED))

    let bufferSize = 4 + MemoryLayout<Int64>.size
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    let result = buffer.withUnsafeMutableBytes { rawBuffer in
        withUnsafeMutablePointer(to: &attributes) { attributesPointer in
            getattrlist(path, attributesPointer, rawBuffer.baseAddress, bufferSize, 0)
        }
    }

    guard result == 0 else {
        return nil
    }

    return buffer.withUnsafeBytes { rawBuffer in
        rawBuffer.loadUnaligned(fromByteOffset: 4, as: Int64.self)
    }
}

private func storageSettingsCachedCategorySize() -> Int64? {
    let byHostURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/ByHost", isDirectory: true)

    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: byHostURL,
        includingPropertiesForKeys: nil
    ) else {
        return nil
    }

    let cacheFiles = contents.filter { url in
        let name = url.lastPathComponent
        return name.hasPrefix("com.apple.settings.storage.") && name.hasSuffix(".plist")
    }

    let totals = cacheFiles.compactMap { cachedCategorySize(in: $0) }
    guard let total = totals.max(), total > 0 else {
        return nil
    }

    return total
}

private func cachedCategorySize(in url: URL) -> Int64? {
    guard
        let data = try? Data(contentsOf: url),
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
        let dictionary = plist as? [String: Any]
    else {
        return nil
    }

    let total = dictionary.values.reduce(Int64(0)) { partial, value in
        guard
            let section = value as? [String: Any],
            let itemSizes = section["ItemSizes"] as? [String: Any]
        else {
            return partial
        }

        return partial + itemSizes.values.reduce(Int64(0)) { sectionTotal, itemSize in
            sectionTotal + int64Value(from: itemSize)
        }
    }

    return total > 0 ? total : nil
}

private func int64Value(from value: Any) -> Int64 {
    if let value = value as? Int64 {
        return value
    }

    if let value = value as? Int {
        return Int64(value)
    }

    if let value = value as? NSNumber {
        return value.int64Value
    }

    return 0
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

    func bytes(onOrBeforeDaysBeforeToday days: Int, now: Date = Date()) -> Int64? {
        guard let date = calendar.date(byAdding: .day, value: -days, to: now) else {
            return nil
        }

        return latestBytes(onOrBefore: date)
    }

    func bytes(monthsBeforeToday months: Int, now: Date = Date()) -> Int64? {
        guard let date = calendar.date(byAdding: .month, value: -months, to: now) else {
            return nil
        }

        return loadHistory()[dateKey(for: date)]
    }

    func bytes(onOrBeforeMonthsBeforeToday months: Int, now: Date = Date()) -> Int64? {
        guard let date = calendar.date(byAdding: .month, value: -months, to: now) else {
            return nil
        }

        return latestBytes(onOrBefore: date)
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

    private func latestBytes(onOrBefore date: Date) -> Int64? {
        let targetDate = calendar.startOfDay(for: date)
        var latestDate: Date?
        var latestBytes: Int64?

        for (key, bytes) in loadHistory() {
            guard let historyDate = historyDate(fromKey: key), historyDate <= targetDate else {
                continue
            }

            if latestDate == nil || historyDate > latestDate! {
                latestDate = historyDate
                latestBytes = bytes
            }
        }

        return latestBytes
    }

    private func historyDate(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
