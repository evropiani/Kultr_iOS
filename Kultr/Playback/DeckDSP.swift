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

    var version: Int { state.withLock { $0.version } }
    func snapshot() -> Snapshot { state.withLock { $0 } }
}

/** What the engine asks of one deck's audio, read by its taps on the audio thread. */
final class DeckParams: @unchecked Sendable {
    struct Values {
        var targetGain: Float = 0
        var bassDb: Float = 0
        var sweepHz: Float = 20
    }

    private let state = OSAllocatedUnfairLock(initialState: Values())

    func set(_ change: (inout Values) -> Void) {
        state.withLock { change(&$0) }
    }

    var values: Values { state.withLock { $0 } }
}

/** One RBJ-cookbook biquad, with state for up to eight channels. */
final class Biquad {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = [Double](repeating: 0, count: 8)
    private var x2 = [Double](repeating: 0, count: 8)
    private var y1 = [Double](repeating: 0, count: 8)
    private var y2 = [Double](repeating: 0, count: 8)
    var bypass = true

    func reset() {
        for i in 0..<8 {
            x1[i] = 0
            x2[i] = 0
            y1[i] = 0
            y2[i] = 0
        }
    }

    private func set(_ nb0: Double, _ nb1: Double, _ nb2: Double, _ na0: Double, _ na1: Double, _ na2: Double) {
        b0 = nb0 / na0
        b1 = nb1 / na0
        b2 = nb2 / na0
        a1 = na1 / na0
        a2 = na2 / na0
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
        let y = b0 * x + b1 * x1[channel] + b2 * x2[channel] - a1 * y1[channel] - a2 * y2[channel]
        x2[channel] = x1[channel]
        x1[channel] = x
        y2[channel] = y1[channel]
        y1[channel] = y
        return y
    }
}

/**
 * Everything a deck does to its audio, in one pass: the bass-swap low shelf,
 * the sweep high-pass, the equaliser, and the fade/ReplayGain level. One per
 * player item, attached to its audio track as an MTAudioProcessingTap; the
 * level ramps across each buffer so fades never click.
 */
final class TapProcessor {
    private let params: DeckParams
    private let eq: EqState

    private var rate = 44_100
    private var channels = 2
    private var interleaved = false
    private var usable = false
    private var gain: Float = 0

    private let bass = Biquad()
    private let sweep = Biquad()
    private let bands = (0..<EQ_BANDS.count).map { _ in Biquad() }
    private var appliedBass = Float.nan
    private var appliedSweep = Float.nan
    private var appliedEq = -1
    private var preamp = 1.0

    init(params: DeckParams, eq: EqState) {
        self.params = params
        self.eq = eq
        gain = params.values.targetGain
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
        gain = params.values.targetGain
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
        let version = eq.version
        if version != appliedEq {
            appliedEq = version
            let snap = eq.snapshot()
            for (index, filter) in bands.enumerated() {
                let g = snap.enabled ? Double(snap.gains[index]) : 0
                let f = Double(EQ_BANDS[index])
                if index == 0 {
                    filter.lowShelf(rate, f, g)
                } else if index == EQ_BANDS.count - 1 {
                    filter.highShelf(rate, f, g)
                } else {
                    filter.peaking(rate, f, g, 1.1)
                }
            }
            preamp = snap.enabled ? pow(10, Double(snap.preampDb) / 20) : 1
        }
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard usable, frames > 0 else { return }
        let values = params.values
        refreshFilters(values)
        let from = gain
        let to = values.targetGain
        gain = to
        let useBass = !bass.bypass
        let useSweep = !sweep.bypass
        let active = bands.filter { !$0.bypass }
        let pre = preamp
        // Nothing to do: unity gain and every filter flat.
        if !useBass && !useSweep && active.isEmpty && abs(pre - 1) < 1e-6 && abs(from - 1) < 1e-5 && abs(to - 1) < 1e-5 { return }
        let step = (to - from) / Float(frames)
        let buffers = UnsafeMutableAudioBufferListPointer(list)

        @inline(__always)
        func run(_ sample: Float, _ channel: Int, _ level: Float) -> Float {
            var x = Double(sample)
            if useBass { x = bass.process(x, channel) }
            if useSweep { x = sweep.process(x, channel) }
            for band in active { x = band.process(x, channel) }
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
