import Foundation

/**
 * Picks tracks to keep the music going when the queue runs out.
 *
 * Candidates come from the server's similarity endpoint first, then the same
 * artist, then the same genre, and finally anything in the library. Whatever
 * we get is re-ranked by how well it mixes, using cached analysis only —
 * never analysing dozens of tracks just to sort them.
 */
@MainActor
struct AutoQueue {
    let graph: AppGraph

    func build(seed: Song, recent: [Song], count: Int = 10) async -> [Song] {
        var exclude = Set(recent.map { $0.id })
        exclude.insert(seed.id)
        var order: [String] = []
        var pool: [String: Song] = [:]
        func add(_ songs: [Song]) {
            for song in songs where !exclude.contains(song.id) && !song.isRadio && pool[song.id] == nil {
                pool[song.id] = song
                order.append(song.id)
            }
        }
        let library = graph.library
        if !seed.isRadio { add(await library.similarSongs(seed.id, count: 60)) }
        if pool.count < count * 3, let artistId = seed.artistId {
            add(Array(await library.songsOfArtistNow(artistId).shuffled().prefix(80)))
        }
        if pool.count < count * 3, let genre = seed.genre { add(await library.randomSongs(200, genre: genre)) }
        if pool.count < count * 3 { add(await library.randomSongs(200)) }
        if pool.isEmpty { return [] }

        let analyses = await graph.analysis.cachedMany(order + [seed.id])
        return rankAutoQueue(seed: analyses[seed.id], candidates: order.map { (pool[$0]!, analyses[$0]) }, count: count)
    }
}
