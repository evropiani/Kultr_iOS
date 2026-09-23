import Foundation
import SQLite3

/** A tiny SQLite wrapper: one connection, serialised by a recursive lock. */

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

protocol SQLiteBindable {
    var sqliteValue: SQLiteValue { get }
}

extension String: SQLiteBindable {
    var sqliteValue: SQLiteValue { .text(self) }
}

extension Int: SQLiteBindable {
    var sqliteValue: SQLiteValue { .integer(Int64(self)) }
}

extension Int64: SQLiteBindable {
    var sqliteValue: SQLiteValue { .integer(self) }
}

extension Double: SQLiteBindable {
    var sqliteValue: SQLiteValue { .real(self) }
}

extension Bool: SQLiteBindable {
    var sqliteValue: SQLiteValue { .integer(self ? 1 : 0) }
}

extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {
    var sqliteValue: SQLiteValue {
        switch self {
        case .none: return .null
        case .some(let value): return value.sqliteValue
        }
    }
}

struct SQLiteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func string(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    func text(_ index: Int32) -> String {
        string(index) ?? ""
    }

    func int(_ index: Int32) -> Int? {
        isNull(index) ? nil : Int(sqlite3_column_int64(statement, index))
    }

    func int64(_ index: Int32) -> Int64? {
        isNull(index) ? nil : sqlite3_column_int64(statement, index)
    }

    func double(_ index: Int32) -> Double? {
        isNull(index) ? nil : sqlite3_column_double(statement, index)
    }

    func bool(_ index: Int32) -> Bool? {
        isNull(index) ? nil : sqlite3_column_int64(statement, index) != 0
    }
}

final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError(message: "Could not open the library database: \(message)")
        }
        handle = db
        sqlite3_busy_timeout(db, 5000)
        try? executeScript("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    private func db() throws -> OpaquePointer {
        guard let handle else { throw SQLiteError(message: "The library database is closed.") }
        return handle
    }

    private func errorMessage() -> String {
        guard let handle else { return "closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(try db(), sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError(message: "SQL error: \(errorMessage()) in \(sql)")
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer, _ args: [SQLiteBindable]) {
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg.sqliteValue {
            case .null: sqlite3_bind_null(statement, index)
            case .integer(let value): sqlite3_bind_int64(statement, index, value)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            }
        }
    }

    func executeScript(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(try db(), sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage()
            sqlite3_free(error)
            throw SQLiteError(message: "SQL error: \(message)")
        }
    }

    @discardableResult
    func execute(_ sql: String, _ args: [SQLiteBindable] = []) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, args)
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError(message: "SQL error: \(errorMessage())")
        }
        return Int(sqlite3_changes(try db()))
    }

    /** Run one statement for many rows, prepared once, inside a transaction. */
    func executeMany(_ sql: String, _ rows: [[SQLiteBindable]]) throws {
        if rows.isEmpty { return }
        try transaction {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            for args in rows {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(statement, args)
                let rc = sqlite3_step(statement)
                guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                    throw SQLiteError(message: "SQL error: \(errorMessage())")
                }
            }
        }
    }

    func query<T>(_ sql: String, _ args: [SQLiteBindable] = [], _ map: (SQLiteRow) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, args)
        var out: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                out.append(try map(SQLiteRow(statement: statement)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError(message: "SQL error: \(errorMessage())")
            }
        }
        return out
    }

    func scalarInt(_ sql: String, _ args: [SQLiteBindable] = []) throws -> Int {
        try query(sql, args) { $0.int(0) ?? 0 }.first ?? 0
    }

    var lastInsertRowId: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return handle.map { sqlite3_last_insert_rowid($0) } ?? 0
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if transactionDepth > 0 {
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            return try body()
        }
        try executeScript("BEGIN IMMEDIATE")
        transactionDepth = 1
        do {
            let result = try body()
            transactionDepth = 0
            try executeScript("COMMIT")
            return result
        } catch {
            transactionDepth = 0
            try? executeScript("ROLLBACK")
            throw error
        }
    }
}
