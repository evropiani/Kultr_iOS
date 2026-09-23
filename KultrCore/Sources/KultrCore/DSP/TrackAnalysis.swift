import Foundation

/**
 * Bump this whenever the DSP changes in a way that invalidates cached numbers.
 * Cached entries with an older version are recomputed on demand.
 */
let ANALYSIS_VERSION = 4

/** Bitrate requested for analysis streams — small, fast and plenty accurate. */
let ANALYSIS_BITRATE = 96

/** Target rate for analysis; 22.05 kHz mono is plenty for tempo and key. */
let ANALYSIS_TARGET_RATE = 22050

enum BpmSource: String, Codable, Hashable {
    case dsp = "DSP"
    case tag = "TAG"
}

/** Everything InjeKt knows about one track. */
struct TrackAnalysis: Codable, Hashable {
    var songId: String
    var version: Int = ANALYSIS_VERSION
    var analysedAt: Int64
    var bpmSource: BpmSource
    var duration: Double
    var bpm: Double
    var bpmConfidence: Double
    var beatOffset: Double
    var downbeatOffset: Double
    var outroDownbeat: Double
    var key: Int
    var keyName: String
    var mode: KeyMode
    var keyConfidence: Double
    var camelot: String
    var energy: Double
    var brightness: Double
    var peak: Double
    var introEnd: Double
    var outroStart: Double

    var isCurrent: Bool { version == ANALYSIS_VERSION }

    /**
     * Turn a raw DSP pass into a stored analysis. Navidrome exposes a BPM
     * tag; it is trusted when our own estimate is shaky.
     */
    static func from(song: Song, pcm: PcmAnalysis, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> TrackAnalysis {
        let tagBpm: Double? = song.bpm.flatMap { (40...220).contains($0) ? Double($0) : nil }
        let useTag = tagBpm != nil && pcm.bpmConfidence < 0.45
        let serverDuration = song.duration.flatMap { $0 > 0 ? Double($0) : nil }
        return TrackAnalysis(
            songId: song.id,
            analysedAt: now,
            bpmSource: useTag ? .tag : .dsp,
            // Prefer the server's duration; decoded duration can drift on VBR files.
            duration: serverDuration ?? pcm.duration,
            bpm: useTag ? tagBpm! : pcm.bpm,
            bpmConfidence: useTag ? 0.8 : pcm.bpmConfidence,
            beatOffset: pcm.beatOffset,
            downbeatOffset: pcm.downbeatOffset,
            outroDownbeat: pcm.outroDownbeat,
            key: pcm.key,
            keyName: pcm.keyName,
            mode: pcm.mode,
            keyConfidence: pcm.keyConfidence,
            camelot: pcm.camelot,
            energy: pcm.energy,
            brightness: pcm.brightness,
            peak: pcm.peak,
            introEnd: pcm.introEnd,
            outroStart: pcm.outroStart
        )
    }
}

/**
 * Collects decoded PCM and folds it into mono at roughly
 * [ANALYSIS_TARGET_RATE], by averaging channels and then blocks of samples.
 * Averaging is a crude low-pass, which is exactly enough: tempo and key
 * detection look at onsets below a few kHz.
 */
final class MonoAccumulator {
    private let channels: Int
    private let factor: Int
    let sampleRate: Int

    private var buffer: [Float] = []
    private var acc = 0.0
    private var accCount = 0

    init(inputRate: Int, channels: Int, targetRate: Int = ANALYSIS_TARGET_RATE) {
        self.channels = max(1, channels)
        factor = max(1, Int((Double(inputRate) / Double(targetRate)).rounded()))
        sampleRate = inputRate / factor
        buffer.reserveCapacity(1 << 16)
    }

    var length: Int { buffer.count }

    /** Add interleaved 16-bit frames. */
    func addPcm16(_ samples: [Int16], count: Int? = nil) {
        let total = count ?? samples.count
        var i = 0
        while i + channels <= total {
            var sum = 0
            for c in 0..<channels { sum += Int(samples[i + c]) }
            push(Double(sum) / (Double(channels) * 32768))
            i += channels
        }
    }

    /** Add interleaved float frames. */
    func addFloat(_ samples: [Float], count: Int? = nil) {
        let total = count ?? samples.count
        var i = 0
        while i + channels <= total {
            var sum = 0.0
            for c in 0..<channels { sum += Double(samples[i + c]) }
            push(sum / Double(channels))
            i += channels
        }
    }

    /** Add non-interleaved float frames: one pointer per channel. */
    func addPlanar(_ channelData: [UnsafePointer<Float>], frames: Int) {
        guard !channelData.isEmpty else { return }
        let count = Double(channelData.count)
        for f in 0..<frames {
            var sum = 0.0
            for data in channelData { sum += Double(data[f]) }
            push(sum / count)
        }
    }

    private func push(_ value: Double) {
        acc += value
        accCount += 1
        if accCount == factor {
            buffer.append(Float(acc / Double(factor)))
            acc = 0
            accCount = 0
        }
    }

    func toArray() -> [Float] { buffer }
}
