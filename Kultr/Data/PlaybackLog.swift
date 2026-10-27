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
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var parts = ["iOS crash report"]
                if let reason = crash.terminationReason { parts.append(reason) }
                if let type = crash.exceptionType { parts.append("exception \(type)") }
                if let code = crash.exceptionCode { parts.append("code \(code)") }
                if let signal = crash.signal { parts.append("signal \(signal)") }
                parts.append("at " + Self.frames(crash.callStackTree))
                PlaybackLog.note(parts.joined(separator: " · "))
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                PlaybackLog.note("iOS report: Kultr used \(cpu.totalCPUTime) of processor time in \(cpu.totalSampledTime) · at \(Self.frames(cpu.callStackTree))")
            }
            for hang in payload.hangDiagnostics ?? [] {
                PlaybackLog.note("iOS report: Kultr hung for \(hang.hangDuration) · at \(Self.frames(hang.callStackTree))")
            }
        }
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /** The innermost few frames of the stack that matters, as binary+offset, to look up later. */
    private static func frames(_ tree: MXCallStackTree) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()) as? [String: Any],
              let stacks = json["callStacks"] as? [[String: Any]],
              let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first,
              var frame = (stack["callStackRootFrames"] as? [[String: Any]])?.first
        else { return "?" }
        var out: [String] = []
        while out.count < 10 {
            let binary = frame["binaryName"] as? String ?? "?"
            let offset = frame["offsetIntoBinaryTextSegment"].map { "\($0)" } ?? "?"
            out.append("\(binary)+\(offset)")
            guard let sub = (frame["subFrames"] as? [[String: Any]])?.first else { break }
            frame = sub
        }
        return out.joined(separator: " < ")
    }
}
