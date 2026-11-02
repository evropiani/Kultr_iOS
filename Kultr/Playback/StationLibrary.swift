import Foundation
import Observation
import SwiftUI

/**
 * Stations: yours (from Settings), plus one per decade the library has enough
 * music from, and the tracks that fit each. Matching reads the whole library
 * and every analysis, so it runs off the main thread and only again when the
 * library, the analysis or the stations change.
 */
@MainActor
@Observable
final class StationLibrary {
    @ObservationIgnored private unowned let graph: AppGraph

    /** A station per decade, from the years in the library. */
    private(set) var decades: [Station] = []
    /** How many tracks fit each station, by id; missing while counting. */
    private(set) var counts: [String: Int] = [:]
    @ObservationIgnored private var countedKey = ""
    @ObservationIgnored private var counting: Task<Void, Never>?

    init(graph: AppGraph) {
        self.graph = graph
    }

    /** Every station, yours first, in dial order. */
    var all: [Station] { graph.settings.current.stations + decades }

    private var key: String {
        let library = graph.library
        let settings = graph.settings.current
        return "\(library.version):\(library.analysisVersion):\(settings.stations.hashValue):\(settings.annotations.hashValue)"
    }

    /** Count again if anything changed since the last time. */
    func refresh() {
        let key = self.key
        guard key != countedKey, counting == nil else { return }
        let mine = graph.settings.current.stations
        let annotations = graph.settings.current.annotations
        counting = Task { [weak self] in
            guard let self else { return }
            let result = await self.graph.library.read(([Station](), [String: Int]())) { db in
                let songs = db.allSongs()
                var analyses: [String: TrackAnalysis] = [:]
                for analysis in db.allAnalyses(version: ANALYSIS_VERSION) { analyses[analysis.songId] = analysis }
                let decades = decadeStations(songs.compactMap(\.year))
                var counts: [String: Int] = [:]
                for station in mine + decades {
                    let tagged = taggedIds(annotations, tags: station.tags ?? [])
                    let since = addedSinceDay(station.addedDays)
                    counts[station.id] = songs.reduce(0) { $0 + (station.matches($1, analyses[$1.id], tagged: tagged, addedSince: since) ? 1 : 0) }
                }
                return (decades, counts)
            }
            self.decades = result.0
            self.counts = result.1
            self.countedKey = key
            self.counting = nil
            // Something changed while counting.
            if self.key != key { self.refresh() }
        }
    }

    /** How many tracks fit [station] right now, for the editor. */
    func count(_ station: Station) async -> Int {
        await pool(station, playableOnly: false).count
    }

    /** The tracks that fit [station], each with InjeKt's analysis if there is one; offline, only downloaded ones. */
    func pool(_ station: Station, playableOnly: Bool = true) async -> [(Song, TrackAnalysis?)] {
        let reachable = graph.isLocal || graph.network.isOnline
        let downloaded = graph.offline.downloadedIds
        let tagged = taggedIds(graph.settings.current.annotations, tags: station.tags ?? [])
        let since = addedSinceDay(station.addedDays)
        let pool = await graph.library.read([(Song, TrackAnalysis?)]()) { db in
            var analyses: [String: TrackAnalysis] = [:]
            for analysis in db.allAnalyses(version: ANALYSIS_VERSION) { analyses[analysis.songId] = analysis }
            return db.allSongs().compactMap { song in
                let analysis = analyses[song.id]
                return station.matches(song, analysis, tagged: tagged, addedSince: since) ? (song, analysis) : nil
            }
        }
        guard playableOnly, !reachable else { return pool }
        return pool.filter { downloaded.contains($0.0.id) }
    }

    // ------------------------------------------------------------- editing --

    func save(_ station: Station) {
        graph.settings.update { s in
            if let at = s.stations.firstIndex(where: { $0.id == station.id }) {
                s.stations[at] = station
            } else {
                s.stations.append(station)
            }
        }
    }

    func delete(_ station: Station) {
        graph.settings.update { $0.stations.removeAll { $0.id == station.id } }
    }

    func move(from: IndexSet, to: Int) {
        graph.settings.update { $0.stations.move(fromOffsets: from, toOffset: to) }
    }

    func resetToPresets() {
        graph.settings.update { $0.stations = STATION_PRESETS }
    }

    /** Whether [station] is one of yours (editable) rather than a decade. */
    func isMine(_ station: Station) -> Bool {
        graph.settings.current.stations.contains { $0.id == station.id }
    }
}
