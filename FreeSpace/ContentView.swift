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

    let path: String
    private var timer: Timer?

    init(path: String) {
        self.path = path
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let url = URL(fileURLWithPath: path)

        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])

            guard
                let total = values.volumeTotalCapacity,
                let available = values.volumeAvailableCapacityForImportantUsage
            else {
                menuTitle = "N/A"
                freeText = "取得失敗"
                freePercentText = "取得失敗"
                return
            }

            let total64 = Int64(total)
            let freePercent = total64 > 0
                ? (Double(available) / Double(total64)) * 100.0
                : 0.0

            let freeCapacityText = formatCapacity(available)
            freeText = freeCapacityText
            freePercentText = String(format: "%.0f%%", freePercent)
            menuTitle = "\(freeCapacityText) (\(Int(freePercent))%)"
        } catch {
            menuTitle = "ERR"
            freeText = "取得エラー"
            freePercentText = error.localizedDescription
        }
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
