import Accelerate
import AVFoundation
import MediaToolbox
import os

/** Equaliser settings shared by both decks; [version] bumps on every change. */
final class EqState: @unchecked Sendable {
    struct Snapshot {
        var enabled = false
        var gains = [Float](repeating: 0, count: EQ_BANDS.count)
        var preampDb: Float = 0
        var version = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot())

    func update(enabled: Bool, gains: [Double], preamp: Double) {
        let next = (0..<EQ_BANDS.count).map { Float($0 < gains.count ? gains[$0] : 0) }
        state.withLock { s in
            if s.enabled == enabled && s.gains == next && s.preampDb == Float(preamp) { return }
            s.enabled = enabled
            s.gains = next
            s.preampDb = Float(preamp)
            s.version += 1
        }
    }

    /** For the audio thread: never waits; nil while the main thread is writing. */
    func snapshotIfAvailable() -> Snapshot? { state.withLockIfAvailable { $0 } }
}

/** What the engine asks of one deck's audio, read by its taps on the audio thread. */
final class DeckParams: @unchecked Sendable {
    struct Values {
        var targetGain: Float = 0
        var bassDb: Float = 0
        var sweepHz: Float = 20
    }

    private let state = OSAllocatedUnfairLock(initialState: Values())

    /** Applies [change]; true if it changed anything. */
    @discardableResult
    func set(_ change: (inout Values) -> Void) -> Bool {
        state.withLock { values in
            let before = values
            change(&values)
            return before.targetGain != values.targetGain || before.bassDb != values.bassDb || before.sweepHz != values.sweepHz
        }
    }

    var values: Values { state.withLock { $0 } }

    /** For the audio thread: never waits; nil while the main thread is writing. */
    func valuesIfAvailable() -> Values? { state.withLockIfAvailable { $0 } }
}

/**
 * One RBJ-cookbook biquad, with state for up to eight channels. Coefficients
 * and state live in one block allocated up front, so running it on the audio
 * thread never allocates and never goes through Swift's exclusivity checks.
 */
final class Biquad {
    // 0..<5: b0 b1 b2 a1 a2; then four values (x1 x2 y1 y2) per channel.
    private static let stateOffset = 5
    private let block: UnsafeMutablePointer<Double>
    private(set) var bypass = true

    init() {
        block = .allocate(capacity: Self.stateOffset + 8 * 4)
        block.initialize(repeating: 0, count: Self.stateOffset + 8 * 4)
        block[0] = 1
    }

    deinit {
        block.deallocate()
    }

    func reset() {
        for i in Self.stateOffset..<(Self.stateOffset + 8 * 4) { block[i] = 0 }
    }

    private func set(_ nb0: Double, _ nb1: Double, _ nb2: Double, _ na0: Double, _ na1: Double, _ na2: Double) {
        block[0] = nb0 / na0
        block[1] = nb1 / na0
        block[2] = nb2 / na0
        block[3] = na1 / na0
        block[4] = na2 / na0
    }

    func lowShelf(_ rate: Int, _ frequency: Double, _ gainDb: Double) {
        bypass = abs(gainDb) < 0.05
        if bypass { return }
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * min(frequency, Double(rate) * 0.45) / Double(rate)
        let cw = cos(w0)
        let alpha = sin(w0) / 2 * 2.0.squareRoot()
        let sa = 2 * a.squareRoot() * alpha
        set(
            a * ((a + 1) - (a - 1) * cw + sa),
            2 * a * ((a - 1) - (a + 1) * cw),
            a * ((a + 1) - (a - 1) * cw - sa),
            (a + 1) + (a - 1) * cw + sa,
            -2 * ((a - 1) + (a + 1) * cw),
            (a + 1) + (a - 1) * cw - sa
        )
    }

    func highShelf(_ rate: Int, _ frequency: Double, _ gainDb: Double) {
        bypass = abs(gainDb) < 0.05
        if bypass { return }
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * min(frequency, Double(rate) * 0.45) / Double(rate)
        let cw = cos(w0)
        let alpha = sin(w0) / 2 * 2.0.squareRoot()
        let sa = 2 * a.squareRoot() * alpha
        set(
            a * ((a + 1) + (a - 1) * cw + sa),
            -2 * a * ((a - 1) + (a + 1) * cw),
            a * ((a + 1) + (a - 1) * cw - sa),
            (a + 1) - (a - 1) * cw + sa,
            2 * ((a - 1) - (a + 1) * cw),
            (a + 1) - (a - 1) * cw - sa
        )
    }

    func peaking(_ rate: Int, _ frequency: Double, _ gainDb: Double, _ q: Double) {
        bypass = abs(gainDb) < 0.05 || frequency >= Double(rate) * 0.49
        if bypass { return }
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * frequency / Double(rate)
        let cw = cos(w0)
        let alpha = sin(w0) / (2 * q)
        set(1 + alpha * a, -2 * cw, 1 - alpha * a, 1 + alpha / a, -2 * cw, 1 - alpha / a)
    }

    func highPass(_ rate: Int, _ frequency: Double, _ q: Double) {
        bypass = frequency <= 21
        if bypass { return }
        let w0 = 2 * Double.pi * min(frequency, Double(rate) * 0.45) / Double(rate)
        let cw = cos(w0)
        let alpha = sin(w0) / (2 * q)
        set((1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha)
    }

    @inline(__always)
    func process(_ x: Double, _ channel: Int) -> Double {
        let c = block
        let s = block + Self.stateOffset + channel * 4
        let y = c[0] * x + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3]
        s[1] = s[0]
        s[0] = x
        s[3] = s[2]
        s[2] = y
        return y
    }
}

/**
 * Everything a deck does to its audio, in one pass: the bass-swap low shelf,
 * the sweep high-pass, the equaliser, and the fade/ReplayGain level. One per
 * player item, attached to its audio track as an MTAudioProcessingTap; the
 * level ramps across each buffer so fades never click.
 *
 * [process] runs on the audio thread, where waiting or allocating can make
 * the sound drop out: it never blocks on the main thread (if the values are
 * being written that instant it uses the last ones) and never allocates.
 */
final class TapProcessor {
    private let params: DeckParams
    private let eq: EqState

    private var rate = 44_100
    private var channels = 2
    private var interleaved = false
    private var usable = false
    private var gain: Float = 0
    private var latest = DeckParams.Values()

    private let bass = Biquad()
    private let sweep = Biquad()
    private let bands = (0..<EQ_BANDS.count).map { _ in Biquad() }
    /** The bands that are not flat, as indices into [bands]; [activeCount] of them are in use. */
    private let active = UnsafeMutablePointer<Int>.allocate(capacity: EQ_BANDS.count)
    private var activeCount = 0
    private var appliedBass = Float.nan
    private var appliedSweep = Float.nan
    private var appliedEq = -1
    private var preamp = 1.0

    init(params: DeckParams, eq: EqState) {
        self.params = params
        self.eq = eq
        latest = params.values
        gain = latest.targetGain
        active.initialize(repeating: 0, count: EQ_BANDS.count)
    }

    deinit {
        active.deallocate()
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        rate = max(8_000, Int(format.mSampleRate))
        channels = min(8, max(1, Int(format.mChannelsPerFrame)))
        interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        usable = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        appliedBass = .nan
        appliedSweep = .nan
        appliedEq = -1
        bass.reset()
        sweep.reset()
        bands.forEach { $0.reset() }
        latest = params.values
        gain = latest.targetGain
    }

    private func refreshFilters(_ values: DeckParams.Values) {
        if values.bassDb != appliedBass {
            bass.lowShelf(rate, 180, Double(values.bassDb))
            appliedBass = values.bassDb
        }
        if values.sweepHz != appliedSweep {
            sweep.highPass(rate, Double(values.sweepHz), 0.7)
            appliedSweep = values.sweepHz
        }
        guard let snap = eq.snapshotIfAvailable(), snap.version != appliedEq else { return }
        appliedEq = snap.version
        activeCount = 0
        for index in 0..<bands.count {
            let filter = bands[index]
            let g = snap.enabled && index < snap.gains.count ? Double(snap.gains[index]) : 0
            let f = Double(EQ_BANDS[index])
            if index == 0 {
                filter.lowShelf(rate, f, g)
            } else if index == EQ_BANDS.count - 1 {
                filter.highShelf(rate, f, g)
            } else {
                filter.peaking(rate, f, g, 1.1)
            }
            if !filter.bypass {
                active[activeCount] = index
                activeCount += 1
            }
        }
        preamp = snap.enabled ? pow(10, Double(snap.preampDb) / 20) : 1
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard usable, frames > 0 else { return }
        if let values = params.valuesIfAvailable() { latest = values }
        refreshFilters(latest)
        let from = gain
        let to = latest.targetGain
        gain = to
        let useBass = !bass.bypass
        let useSweep = !sweep.bypass
        let filtered = useBass || useSweep || activeCount > 0 || abs(preamp - 1) > 1e-6
        // Nothing to do: unity gain and every filter flat.
        if !filtered && abs(from - 1) < 1e-5 && abs(to - 1) < 1e-5 { return }
        let step = (to - from) / Float(frames)
        let buffers = UnsafeMutableAudioBufferListPointer(list)

        if !filtered {
            // Only the level: one vectorised ramp per channel.
            if interleaved {
                guard let raw = buffers.first?.mData else { return }
                let data = raw.assumingMemoryBound(to: Float.self)
                let n = channels
                let count = min(frames, Int(buffers[0].mDataByteSize) / (4 * n))
                for c in 0..<n {
                    var start = from + step
                    var increment = step
                    vDSP_vrampmul(data + c, vDSP_Stride(n), &start, &increment, data + c, vDSP_Stride(n), vDSP_Length(count))
                }
            } else {
                for buffer in buffers {
                    guard let raw = buffer.mData else { continue }
                    let data = raw.assumingMemoryBound(to: Float.self)
                    let count = min(frames, Int(buffer.mDataByteSize) / 4)
                    var start = from + step
                    var increment = step
                    vDSP_vrampmul(data, 1, &start, &increment, data, 1, vDSP_Length(count))
                }
            }
            return
        }

        let pre = preamp
        let bandCount = activeCount
        let order = active
        @inline(__always)
        func run(_ sample: Float, _ channel: Int, _ level: Float) -> Float {
            var x = Double(sample)
            if useBass { x = bass.process(x, channel) }
            if useSweep { x = sweep.process(x, channel) }
            for i in 0..<bandCount { x = bands[order[i]].process(x, channel) }
            return Float(x * pre) * level
        }

        if interleaved {
            guard let raw = buffers.first?.mData else { return }
            let data = raw.assumingMemoryBound(to: Float.self)
            let n = channels
            let available = Int(buffers[0].mDataByteSize) / (4 * n)
            for f in 0..<min(frames, available) {
                let level = from + step * Float(f + 1)
                for c in 0..<n {
                    data[f * n + c] = run(data[f * n + c], c, level)
                }
            }
        } else {
            for (c, buffer) in buffers.enumerated() where c < 8 {
                guard let raw = buffer.mData else { continue }
                let data = raw.assumingMemoryBound(to: Float.self)
                let count = min(frames, Int(buffer.mDataByteSize) / 4)
                for f in 0..<count {
                    data[f] = run(data[f], c, from + step * Float(f + 1))
                }
            }
        }
    }
}

// ------------------------------------------------------------ the tap glue --

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferList, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    Unmanaged<TapProcessor>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()
        .process(bufferList, frames: Int(numberFramesOut.pointee))
}

enum DeckTap {
    /** An audio mix that runs [processor] over [track], or nil if the tap cannot be made. */
    static func audioMix(for track: AVAssetTrack, processor: TapProcessor) -> AVAudioMix? {
        let info = Unmanaged.passRetained(processor).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: info,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<TapProcessor>.fromOpaque(info).release()
            return nil
        }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }
}
