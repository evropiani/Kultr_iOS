import Foundation

/** What [body] returns, or nil if it takes longer than [seconds]; it is cancelled then. */
@MainActor
func withTimeout<T: Sendable>(_ seconds: Double, _ body: @escaping @MainActor () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
