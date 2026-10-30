import AVFoundation
import Foundation
import MetricKit
import os
import UIKit

/**
 * A diary of playback, kept on the phone: what played, what stopped it, and
 * what iOS did to Kultr in the background. When the music stops by itself,
 * this tells why (Settings → About → Playback log), and it can be shared.
 */
final class PlaybackLog: @unchecked Sendable {
    static let shared = PlaybackLog()

    /** Lines kept: a good few days of listening. */
    private static let keep = 1_500

    private let queue = DispatchQueue(label: "kultr.playback-log", qos: .utility)
    private let file: URL
    private var lines: [String] = []
    private let stamp: DateFormatter
    private let reports = ExitReports()

    private init() {
        file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-log.txt")
        stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "MM-dd HH:mm:ss"
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            lines = text.split(separator: "\n").suffix(Self.keep).map(String.init)
        }
    }

    static func note(_ text: String) {
        shared.add(text)
    }

    func add(_ text: String) {
        let date = Date()
        queue.async { [self] in
            let line = "\(stamp.string(from: date))  \(text)"
            lines.append(line)
            if lines.count > Self.keep + 300 {
                lines.removeFirst(lines.count - Self.keep)
                rewrite()
            } else {
                append(line)
            }
        }
    }

    var text: String {
        queue.sync { lines.joined(separator: "\n") }
    }

    func clear() {
        queue.async { [self] in
            lines = []
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func append(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            try? data.write(to: file)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func rewrite() {
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: file, options: .atomic)
    }

    // -------------------------------------------------------------- launch --

    /** At launch: note how Kultr's last run ended, and start listening to iOS. */
    @MainActor
    func start(_ application: UIApplication) {
        let how = application.applicationState == .background ? "in the background (a widget, or the Lock Screen)" : "on screen"
        add("Kultr \(appVersion) (\(appBuild)) started \(how), iOS \(UIDevice.current.systemVersion)")
        checkLastRun()
        MXMetricManager.shared.add(reports)
        // Reports iOS handed over before, to this Kultr or an older one: written
        // down once each, with the code they point at in full.
        let past = MXMetricManager.shared.pastDiagnosticPayloads
        let reports = self.reports
        queue.async { reports.didReceive(past) }

        let center = NotificationCenter.default
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "Went to the background"),
            (UIApplication.willEnterForegroundNotification, "Came back to the front"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "Phone locked"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "Phone unlocked"),
            (UIApplication.didReceiveMemoryWarningNotification, "iOS is short of memory and asked Kultr to free some"),
            (AVAudioSession.mediaServicesWereLostNotification, "iOS's audio system stopped working"),
            (AVAudioSession.mediaServicesWereResetNotification, "iOS's audio system restarted"),
        ]
        for (name, text) in events {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.add("\(text) · \(Self.memory())")
            }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.add("Kultr is being closed (swiped away, or by iOS)")
            self?.heartbeat(playing: false, background: false)
        }
    }

    // ------------------------------------------------------- staying alive --

    private static let aliveKey = "log.aliveAt"
    private static let playingKey = "log.playing"
    private static let backgroundKey = "log.background"

    /** Every few seconds while music plays, and whenever it starts or stops. */
    func heartbeat(playing: Bool, background: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: Self.aliveKey)
        defaults.set(playing, forKey: Self.playingKey)
        defaults.set(background, forKey: Self.backgroundKey)
    }

    /** Kultr can't write anything when iOS ends it; the heartbeat it left says it was playing then. */
    private func checkLastRun() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.playingKey) else { return }
        defaults.set(false, forKey: Self.playingKey)
        let last = Date(timeIntervalSince1970: defaults.double(forKey: Self.aliveKey))
        let place = defaults.bool(forKey: Self.backgroundKey) ? "in the background" : "on screen"
        add(
            "Last time, Kultr stopped running while music played \(place), within seconds of \(stamp.string(from: last)): "
                + "iOS ended it, it crashed, or it was swiped away"
        )
    }

    /** How much memory Kultr uses, and how much more iOS would let it have. */
    static func memory() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let used = result == KERN_SUCCESS ? "\(info.phys_footprint / 1_048_576) MB" : "?"
        return "memory \(used), \(os_proc_available_memory() / 1_048_576) MB to spare"
    }
}

/**
 * iOS's own reports on Kultr through MetricKit: how often it ended in the
 * background and why (once a day), and crashes (at the next launch). Only
 * there when Share With App Developers is on in Settings → Privacy &
 * Security → Analytics & Improvements.
 */
private final class ExitReports: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics?.backgroundExitData else { continue }
            let reasons: [(String, Int)] = [
                ("too much memory", exits.cumulativeMemoryResourceLimitExitCount),
                ("iOS needed the memory", exits.cumulativeMemoryPressureExitCount),
                ("too much processor time", exits.cumulativeCPUResourceLimitExitCount),
                ("unresponsive", exits.cumulativeAppWatchdogExitCount),
                ("background time ran out", exits.cumulativeBackgroundTaskAssertionTimeoutExitCount),
                ("suspended holding a file lock", exits.cumulativeSuspendedWithLockedFileExitCount),
                ("crashed (memory access)", exits.cumulativeBadAccessExitCount),
                ("crashed (illegal instruction)", exits.cumulativeIllegalInstructionExitCount),
                ("ended abnormally", exits.cumulativeAbnormalExitCount),
                ("ended normally", exits.cumulativeNormalAppExitCount),
            ]
            let found = reasons.filter { $0.1 > 0 }.map { "\($0.0) ×\($0.1)" }
            if found.isEmpty { continue }
            PlaybackLog.note("iOS report, \(Self.day(payload.timeStampBegin)) to \(Self.day(payload.timeStampEnd)): Kultr ended in the background: \(found.joined(separator: ", "))")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in Self.unseen(payloads) {
            for crash in payload.crashDiagnostics ?? [] {
                var parts = ["iOS crash report"]
                if let reason = crash.terminationReason { parts.append(reason) }
                if let type = crash.exceptionType { parts.append("exception \(type)") }
                if let code = crash.exceptionCode { parts.append("code \(code)") }
                if let signal = crash.signal { parts.append("signal \(signal)") }
                parts.append("at " + Self.hotPaths(crash.callStackTree))
                PlaybackLog.note(parts.joined(separator: " · "))
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                PlaybackLog.note(
                    "iOS report from \(Self.day(payload.timeStampEnd)): Kultr used \(cpu.totalCPUTime) of processor time in \(cpu.totalSampledTime), "
                        + "so iOS closed it · where the time went: \(Self.hotPaths(cpu.callStackTree))"
                )
            }
            for hang in payload.hangDiagnostics ?? [] {
                PlaybackLog.note("iOS report from \(Self.day(payload.timeStampEnd)): Kultr hung for \(hang.hangDuration) · at \(Self.hotPaths(hang.callStackTree))")
            }
        }
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /** Diagnostics not written down yet: iOS hands the same ones over again in pastDiagnosticPayloads. */
    private static func unseen(_ payloads: [MXDiagnosticPayload]) -> [MXDiagnosticPayload] {
        let key = "log.diagnosticsSeen"
        let defaults = UserDefaults.standard
        var seen = Set(defaults.array(forKey: key) as? [Double] ?? [])
        let fresh = payloads.filter { seen.insert($0.timeStampEnd.timeIntervalSince1970).inserted }
        if !fresh.isEmpty { defaults.set(Array(seen.sorted().suffix(200)), forKey: key) }
        return fresh
    }

    /**
     * Where the time went: for the busiest few threads (or the one that
     * crashed), the path most samples took, from the innermost frame
     * outwards, as binary+offset to look up in that build.
     */
    private static func hotPaths(_ tree: MXCallStackTree) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()) as? [String: Any],
              let stacks = json["callStacks"] as? [[String: Any]]
        else { return "?" }
        let attributed = stacks.filter { $0["threadAttributed"] as? Bool == true }
        let roots = (attributed.isEmpty ? stacks : attributed).flatMap { $0["callStackRootFrames"] as? [[String: Any]] ?? [] }
        func samples(_ frame: [String: Any]) -> Int { frame["sampleCount"] as? Int ?? 1 }
        func name(_ frame: [String: Any]) -> String {
            "\(frame["binaryName"] as? String ?? "?")+\(frame["offsetIntoBinaryTextSegment"].map { "\($0)" } ?? "?")"
        }
        let total = max(1, roots.map(samples).reduce(0, +))
        let paths = roots.sorted { samples($0) > samples($1) }.prefix(3).map { root -> String in
            var path = [root]
            while let children = path.last?["subFrames"] as? [[String: Any]],
                  let busiest = children.max(by: { samples($0) < samples($1) }) {
                path.append(busiest)
            }
            let share = samples(root) * 100 / total
            return "[\(share)% of samples] " + path.suffix(18).reversed().map(name).joined(separator: " < ")
        }
        return paths.isEmpty ? "?" : paths.joined(separator: "  ")
    }
}

/**
 * Processor time per thread, to tell where it goes while Kultr plays in the
 * background, where iOS closes an app that keeps a core busy for a minute.
 * Create and use it on the main thread.
 */
final class ThreadTimes {
    private var last: [UInt64: UInt64] = [:]
    private var lastAt = DispatchTime.now().uptimeNanoseconds
    private let mainId: UInt64

    init() {
        var id: UInt64 = 0
        pthread_threadid_np(nil, &id)
        mainId = id
        _ = sample()
    }

    /** Since the last call: the seconds covered, the share of one core used in all, and the busiest threads. */
    func sample() -> (seconds: Int, percent: Int, busiest: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        let span = Double(max(1, now - lastAt))
        lastAt = now
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return (0, 0, "") }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var times: [UInt64: UInt64] = [:]
        var used: [(String, UInt64)] = []
        for i in 0..<Int(count) {
            let thread = list[i]
            defer { mach_port_deallocate(mach_task_self_, thread) }
            guard let (id, time, name) = Self.info(thread) else { continue }
            times[id] = time
            let before = last[id] ?? 0
            if time > before { used.append((id == mainId ? "main" : (name.isEmpty ? "unnamed" : name), time - before)) }
        }
        last = times
        let total = used.reduce(UInt64(0)) { $0 + $1.1 }
        let busiest = used.sorted { $0.1 > $1.1 }.prefix(4)
            .map { "\($0.0) \(Int(Double($0.1) * 100 / span))%" }
            .joined(separator: ", ")
        return (Int(span / 1e9), Int(Double(total) * 100 / span), busiest)
    }

    private static func info(_ thread: thread_act_t) -> (UInt64, UInt64, String)? {
        var extended = thread_extended_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &extended) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var identifier = thread_identifier_info_data_t()
        var identifierCount = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
        let identified = withUnsafeMutablePointer(to: &identifier) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(identifierCount)) {
                thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &identifierCount)
            }
        }
        let id = identified == KERN_SUCCESS ? identifier.thread_id : UInt64(thread)
        let name = withUnsafeBytes(of: extended.pth_name) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (id, extended.pth_user_time + extended.pth_system_time, name)
    }
}
