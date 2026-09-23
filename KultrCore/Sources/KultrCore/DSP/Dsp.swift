import Foundation

/*
 * Signal analysis used by InjeKt, ported from Kultr's web and Android clients.
 *
 * Everything here works on mono PCM and has no platform dependencies. The goal
 * is not musicological perfection — it is to know, for every track, roughly:
 *
 *   - how fast it is (BPM) and where its beats/downbeats land,
 *   - what key it is in (for harmonic mixing),
 *   - how loud and how bright it is (for level and EQ matching),
 *   - where the intro stops being an intro and the outro starts.
 */

private let pitchNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

/** Camelot wheel position per pitch class, for major and minor keys. */
private let majorCamelot = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
private let minorCamelot = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]

/** Krumhansl–Schmuckler key profiles. */
private let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
private let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.6, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

let FFT_SIZE = 1024
let HOP_SIZE = 512

/** Iterative radix-2 Cooley–Tukey FFT with precomputed twiddle tables. */
final class Fft {
    let size: Int
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let rev: [Int]

    init(size: Int) {
        precondition(size >= 2 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.size = size
        cosTable = (0..<(size / 2)).map { Float(cos(-2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<(size / 2)).map { Float(sin(-2 * Double.pi * Double($0) / Double(size))) }
        let bits = size.trailingZeroBitCount
        rev = (0..<size).map { i in
            var r = 0
            for b in 0..<bits where i & (1 << b) != 0 { r |= 1 << (bits - 1 - b) }
            return r
        }
    }

    /** In-place complex FFT. */
    func transform(_ re: inout [Float], _ im: inout [Float]) {
        let n = size
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                cosTable.withUnsafeBufferPointer { cosT in
                    sinTable.withUnsafeBufferPointer { sinT in
                        rev.withUnsafeBufferPointer { rev in
                            for i in 0..<n {
                                let j = rev[i]
                                if j > i {
                                    var tmp = re[i]
                                    re[i] = re[j]
                                    re[j] = tmp
                                    tmp = im[i]
                                    im[i] = im[j]
                                    im[j] = tmp
                                }
                            }
                            var len = 2
                            while len <= n {
                                let half = len >> 1
                                let step = n / len
                                var i = 0
                                while i < n {
                                    var k = 0
                                    for j in 0..<half {
                                        let c = cosT[k]
                                        let s = sinT[k]
                                        let ar = re[i + j + half]
                                        let ai = im[i + j + half]
                                        let tr = ar * c - ai * s
                                        let ti = ar * s + ai * c
                                        re[i + j + half] = re[i + j] - tr
                                        im[i + j + half] = im[i + j] - ti
                                        re[i + j] += tr
                                        im[i + j] += ti
                                        k += step
                                    }
                                    i += len
                                }
                                len <<= 1
                            }
                        }
                    }
                }
            }
        }
    }
}

private func hannWindow(_ size: Int) -> [Float] {
    (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size - 1))) }
}

struct SpectralFeatures {
    /** Onset strength per frame (spectral flux, half-wave rectified). */
    let onset: [Float]
    /** RMS per frame, linear. */
    let rms: [Float]
    /** Spectral centroid per frame, in Hz. */
    let centroid: [Float]
    /** Summed chroma vector over the whole signal. */
    let chroma: [Float]
    /** Frames per second of the frame-rate features. */
    let fps: Double
}

/** One STFT pass that produces every frame-rate feature we need. */
func spectralFeatures(_ pcm: [Float], sampleRate: Int) -> SpectralFeatures {
    let fft = Fft(size: FFT_SIZE)
    let window = hannWindow(FFT_SIZE)
    let frames = max(1, Int(floor(Double(pcm.count - FFT_SIZE) / Double(HOP_SIZE))) + 1)
    var onset = [Float](repeating: 0, count: frames)
    var rms = [Float](repeating: 0, count: frames)
    var centroid = [Float](repeating: 0, count: frames)
    var chroma = [Float](repeating: 0, count: 12)

    var re = [Float](repeating: 0, count: FFT_SIZE)
    var im = [Float](repeating: 0, count: FFT_SIZE)
    let bins = FFT_SIZE / 2
    var prevMag = [Float](repeating: 0, count: bins)
    var mag = [Float](repeating: 0, count: bins)
    let binHz = Double(sampleRate) / Double(FFT_SIZE)

    // Pre-map bins to pitch classes once; bins outside the musical range map to -1.
    let binPitch: [Int] = (0..<bins).map { b in
        let hz = Double(b) * binHz
        if hz < 65 || hz > 2200 { return -1 }
        let midi = 69 + 12 * log2(hz / 440)
        return ((Int(midi.rounded()) % 12) + 12) % 12
    }

    pcm.withUnsafeBufferPointer { pcm in
        for f in 0..<frames {
            let start = f * HOP_SIZE
            var sumSquares = 0.0
            for i in 0..<FFT_SIZE {
                let index = start + i
                let sample: Float = index < pcm.count ? pcm[index] : 0
                sumSquares += Double(sample * sample)
                re[i] = sample * window[i]
                im[i] = 0
            }
            rms[f] = Float(sqrt(sumSquares / Double(FFT_SIZE)))

            fft.transform(&re, &im)

            var flux = 0.0
            var weighted = 0.0
            var total = 0.0
            let sampleChroma = (f & 3) == 0
            for b in 0..<bins {
                let m = (re[b] * re[b] + im[b] * im[b]).squareRoot()
                mag[b] = m
                let diff = m - prevMag[b]
                if diff > 0 { flux += Double(diff) }
                weighted += Double(m) * Double(b) * binHz
                total += Double(m)
                let pc = binPitch[b]
                // Chroma only needs a coarse picture; sample every 4th frame.
                if pc >= 0 && sampleChroma { chroma[pc] += m * m }
            }
            onset[f] = Float(flux)
            centroid[f] = total > 1e-9 ? Float(weighted / total) : 0
            swap(&mag, &prevMag)
        }
    }

    return SpectralFeatures(onset: onset, rms: rms, centroid: centroid, chroma: chroma, fps: Double(sampleRate) / Double(HOP_SIZE))
}

/** Subtract a moving average and half-wave rectify, which sharpens onsets. */
func normalizeOnset(_ onset: [Float], fps: Double) -> [Float] {
    var out = [Float](repeating: 0, count: onset.count)
    let half = max(1, Int((fps * 0.15).rounded()))
    let span = half * 2 + 1
    var sum = 0.0
    for i in 0..<onset.count {
        sum += Double(onset[i])
        if i >= span { sum -= Double(onset[i - span]) }
        let count = min(i + 1, span)
        let mean = sum / Double(count)
        out[i] = Float(max(0.0, Double(onset[i]) - mean))
    }
    let peak = out.max() ?? 0
    if peak > 0 {
        for i in 0..<out.count { out[i] /= peak }
    }
    return out
}

/** Autocorrelation at an integer lag, normalised by the overlap length. */
private func acfAt(_ signal: UnsafeBufferPointer<Float>, _ lag: Int) -> Double {
    let limit = signal.count - lag
    if limit <= 0 { return 0 }
    var sum: Float = 0
    var i = 0
    while i < limit {
        sum += signal[i] * signal[i + lag]
        i += 1
    }
    return Double(sum) / Double(limit)
}

struct TempoResult: Hashable {
    let bpm: Double
    let confidence: Double
    /** Seconds from the start of the signal to the first beat. */
    let beatOffset: Double
    /** Seconds from the start of the signal to the first downbeat (4/4 assumed). */
    let downbeatOffset: Double
    /**
     * A downbeat anchored near the END of the track. Even a 0.3% tempo error
     * puts a grid fitted at 0:00 a whole beat out by 4:00, so the phase is
     * fitted twice and InjeKt uses whichever anchor is closer.
     */
    let outroDownbeat: Double
}

private struct CombFit {
    let magnitude: Double
    let offset: Double
}

/**
 * Correlate the onset envelope against a unit pulse train of the given period
 * over [from, to). The magnitude says how well that period fits; the argument
 * gives the phase, i.e. where the pulses actually land.
 */
private func combFit(_ env: UnsafeBufferPointer<Float>, _ period: Double, _ from: Int, _ to: Int) -> CombFit {
    var re = 0.0
    var im = 0.0
    let step = 2 * Double.pi / period
    if from < to {
        for n in from..<to {
            let value = Double(env[n])
            if value == 0 { continue }
            let angle = step * Double(n - from)
            re += value * cos(angle)
            im += value * sin(angle)
        }
    }
    let phase = atan2(im, re)
    var offset = phase / (2 * Double.pi) * period
    offset = (offset.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
    return CombFit(magnitude: (re * re + im * im).squareRoot(), offset: Double(from) + offset)
}

func detectTempo(_ onsetNorm: [Float], fps: Double) -> TempoResult {
    onsetNorm.withUnsafeBufferPointer { detectTempo($0, fps: fps) }
}

private func detectTempo(_ onsetNorm: UnsafeBufferPointer<Float>, fps: Double) -> TempoResult {
    let minBpm = 62.0
    let maxBpm = 190.0

    let minLag = max(2, Int(floor(60 / maxBpm * fps)))
    let maxLag = min(onsetNorm.count / 2, Int(ceil(60 / minBpm * fps)))
    if maxLag <= minLag + 1 {
        return TempoResult(bpm: 120, confidence: 0, beatOffset: 0, downbeatOffset: 0, outroDownbeat: 0)
    }

    // Autocorrelate once on the integer lag grid; everything else reads from it.
    var acf = [Double](repeating: 0, count: maxLag + 2)
    for lag in minLag...(maxLag + 1) { acf[lag] = acfAt(onsetNorm, lag) }

    var bestLag = minLag
    var bestScore = -Double.infinity
    var scoreSum = 0.0
    var scoreCount = 0

    for lag in minLag...maxLag {
        var score = acf[lag]
        let double = lag * 2
        if double <= maxLag { score += 0.55 * acf[double] }
        let half = Int((Double(lag) / 2).rounded())
        if half >= minLag { score += 0.25 * acf[half] }
        // Prior: real dance/pop tempi cluster around 120, which suppresses the
        // classic half/double-time confusion without hard-coding a range.
        let bpm = 60 * fps / Double(lag)
        score *= exp(-0.5 * pow(log2(bpm / 122) / 0.5, 2))
        scoreSum += score
        scoreCount += 1
        if score > bestScore {
            bestScore = score
            bestLag = lag
        }
    }

    // The autocorrelation peak only has to pick the right octave; the precise
    // period comes from a matched pulse train, whose response sharpens with
    // the length of the track.
    let length = onsetNorm.count
    var period = Double(bestLag)
    var bestMagnitude = -1.0
    let low = Double(bestLag) * 0.96
    let high = Double(bestLag) * 1.04
    let step = max(0.0005, Double(bestLag) * 0.0002)
    var candidate = low
    while candidate <= high {
        let magnitude = combFit(onsetNorm, candidate, 0, length).magnitude
        if magnitude > bestMagnitude {
            bestMagnitude = magnitude
            period = candidate
        }
        candidate += step
    }

    let bestBpm = 60 * fps / period
    let meanScore = scoreCount > 0 ? scoreSum / Double(scoreCount) : 0
    let confidence = meanScore > 1e-12 ? min(1.0, (bestScore / meanScore - 1) / 4) : 0

    let beatOffset = combFit(onsetNorm, period, 0, length).offset

    // Which of the four beats in a bar carries the most weight.
    var bestBar = 0
    var bestBarScore = -1.0
    for b in 0..<4 {
        var sum = 0.0
        var pos = beatOffset + Double(b) * period
        while pos < Double(length) {
            let index = Int(pos.rounded())
            if index >= 0 && index < length { sum += Double(onsetNorm[index]) }
            pos += period * 4
        }
        if sum > bestBarScore {
            bestBarScore = sum
            bestBar = b
        }
    }

    // Re-fit the phase over the tail so the mix-out grid is anchored where the
    // transition actually happens rather than four minutes earlier.
    let tailFrom = max(0, length - Int((fps * 75).rounded()))
    let tail = combFit(onsetNorm, period, tailFrom, length)
    let bar = period * 4
    // Keep the same beat-in-bar as the global fit.
    let barPhase = (beatOffset + Double(bestBar) * period).truncatingRemainder(dividingBy: bar)
    let tailInBar = tail.offset.truncatingRemainder(dividingBy: bar)
    var outroDownbeat = tail.offset + ((barPhase - tailInBar + bar).truncatingRemainder(dividingBy: bar))
    if outroDownbeat >= Double(length) { outroDownbeat -= bar }

    return TempoResult(
        bpm: (bestBpm * 100).rounded() / 100,
        confidence: (max(0, confidence) * 100).rounded() / 100,
        beatOffset: beatOffset / fps,
        downbeatOffset: (beatOffset + Double(bestBar) * period) / fps,
        outroDownbeat: max(0, outroDownbeat) / fps
    )
}

enum KeyMode: String, Codable, Hashable {
    case major = "MAJOR"
    case minor = "MINOR"
}

struct KeyResult: Hashable {
    let key: Int
    let mode: KeyMode
    let confidence: Double
    let name: String
    let camelot: String
}

private func pearson(_ a: [Double], _ b: [Double]) -> Double {
    let n = Double(a.count)
    let meanA = a.reduce(0, +) / n
    let meanB = b.reduce(0, +) / n
    var num = 0.0
    var denA = 0.0
    var denB = 0.0
    for i in 0..<a.count {
        let da = a[i] - meanA
        let db = b[i] - meanB
        num += da * db
        denA += da * da
        denB += db * db
    }
    let den = (denA * denB).squareRoot()
    return den > 1e-12 ? num / den : 0
}

func detectKey(_ chroma: [Float]) -> KeyResult {
    var rotated = [Double](repeating: 0, count: 12)
    var bestKey = 0
    var bestMode = KeyMode.major
    var bestScore = -2.0
    var second = -2.0

    for root in 0..<12 {
        for mode in [KeyMode.major, KeyMode.minor] {
            let profile = mode == .major ? majorProfile : minorProfile
            for i in 0..<12 { rotated[i] = Double(chroma[(root + i) % 12]) }
            let score = pearson(rotated, profile)
            if score > bestScore {
                second = bestScore
                bestScore = score
                bestKey = root
                bestMode = mode
            } else if score > second {
                second = score
            }
        }
    }

    let confidence = ((bestScore - second) * 500).rounded() / 100
    let camelot = bestMode == .major ? "\(majorCamelot[bestKey])B" : "\(minorCamelot[bestKey])A"
    return KeyResult(
        key: bestKey,
        mode: bestMode,
        confidence: min(1, max(0, confidence)),
        name: pitchNames[bestKey] + (bestMode == .minor ? "m" : ""),
        camelot: camelot
    )
}

struct StructureResult: Hashable {
    /** Seconds at which the intro stops being quiet/sparse. */
    let introEnd: Double
    /** Seconds at which the track starts winding down. */
    let outroStart: Double
    /** Mean loudness over the body of the track, 0..1. */
    let energy: Double
    /** 0..1 perceptual-ish brightness. */
    let brightness: Double
    let peak: Double
}

func detectStructure(rms: [Float], centroid: [Float], fps: Double, sampleRate: Int, duration: Double) -> StructureResult {
    // Smooth the RMS envelope over ~1s so single hits do not look like sections.
    let window = max(1, Int(fps.rounded()))
    var smooth = [Float](repeating: 0, count: rms.count)
    var running = 0.0
    for i in 0..<rms.count {
        running += Double(rms[i])
        if i >= window { running -= Double(rms[i - window]) }
        smooth[i] = Float(running / Double(min(i + 1, window)))
    }

    let sorted = smooth.sorted()
    func at(_ fraction: Double) -> Double {
        let index = Int(floor(Double(sorted.count) * fraction))
        return index >= 0 && index < sorted.count ? Double(sorted[index]) : 0
    }
    let p90 = at(0.9)
    let median = at(0.5)
    let enterThreshold = p90 * 0.42
    let leaveThreshold = p90 * 0.3
    let sustain = Int((fps * 1.5).rounded())

    var introEnd = 0.0
    if smooth.count - sustain > 0 {
        outer: for i in 0..<(smooth.count - sustain) {
            if Double(smooth[i]) < enterThreshold { continue }
            for j in i..<(i + sustain) where Double(smooth[j]) < leaveThreshold {
                continue outer
            }
            introEnd = Double(i) / fps
            break
        }
    }

    var outroStart = duration
    var i = smooth.count - 1
    while i >= sustain {
        if Double(smooth[i]) >= enterThreshold {
            outroStart = min(duration, Double(i + 1) / fps)
            break
        }
        i -= 1
    }

    let peak = Double(rms.max() ?? 0)

    var centroidSum = 0.0
    var centroidCount = 0
    for k in 0..<centroid.count where Double(rms[k]) > median * 0.5 {
        centroidSum += Double(centroid[k])
        centroidCount += 1
    }
    let meanCentroid = centroidCount > 0 ? centroidSum / Double(centroidCount) : 0

    return StructureResult(
        introEnd: min(introEnd, duration * 0.3),
        outroStart: max(outroStart, duration * 0.5),
        energy: min(1, median * 4),
        brightness: min(1, meanCentroid / (Double(sampleRate) / 4)),
        peak: peak
    )
}

struct PcmAnalysis: Hashable {
    let duration: Double
    let bpm: Double
    let bpmConfidence: Double
    let beatOffset: Double
    let downbeatOffset: Double
    let outroDownbeat: Double
    let key: Int
    let keyName: String
    let mode: KeyMode
    let keyConfidence: Double
    let camelot: String
    let energy: Double
    let brightness: Double
    let peak: Double
    let introEnd: Double
    let outroStart: Double
}

/** Full analysis pass over decoded mono PCM. */
func analysePcm(_ pcm: [Float], sampleRate: Int) -> PcmAnalysis {
    let duration = Double(pcm.count) / Double(sampleRate)
    let features = spectralFeatures(pcm, sampleRate: sampleRate)
    let onsetNorm = normalizeOnset(features.onset, fps: features.fps)
    let tempo = detectTempo(onsetNorm, fps: features.fps)
    let key = detectKey(features.chroma)
    let structure = detectStructure(
        rms: features.rms,
        centroid: features.centroid,
        fps: features.fps,
        sampleRate: sampleRate,
        duration: duration
    )
    return PcmAnalysis(
        duration: duration,
        bpm: tempo.bpm,
        bpmConfidence: tempo.confidence,
        beatOffset: tempo.beatOffset,
        downbeatOffset: tempo.downbeatOffset,
        outroDownbeat: tempo.outroDownbeat,
        key: key.key,
        keyName: key.name,
        mode: key.mode,
        keyConfidence: key.confidence,
        camelot: key.camelot,
        energy: structure.energy,
        brightness: structure.brightness,
        peak: structure.peak,
        introEnd: structure.introEnd,
        outroStart: structure.outroStart
    )
}

private let camelotPattern = try! NSRegularExpression(pattern: "^(\\d{1,2})([AB])$")

private func parseCamelot(_ text: String) -> (Int, String)? {
    let ns = text as NSString
    guard let match = camelotPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
          let number = Int(ns.substring(with: match.range(at: 1)))
    else { return nil }
    return (number, ns.substring(with: match.range(at: 2)))
}

/** Distance on the Camelot wheel: 0 = same key, 1 = neighbour, up to 6. */
func camelotDistance(_ a: String, _ b: String) -> Double {
    guard let left = parseCamelot(a), let right = parseCamelot(b) else { return 6 }
    let ring = Double(min(abs(left.0 - right.0), 12 - abs(left.0 - right.0)))
    let relative = left.1 == right.1 ? 0.0 : 1.0
    return ring + relative * (ring == 0 ? 0.5 : 1.0)
}
