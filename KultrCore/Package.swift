// swift-tools-version:5.9
import PackageDescription

// The platform-independent heart of Kultr for iOS: the Subsonic client, the
// settings model, InjeKt's analysis and planner, the two-deck engine, the
// library sync and the SQLite mirror. The app target compiles these same
// sources directly; this package exists so they can be unit-tested with
// `swift test` on a Mac, without a simulator.
let package = Package(
    name: "KultrCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KultrCore", targets: ["KultrCore"]),
    ],
    targets: [
        .target(
            name: "KultrCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "KultrCoreTests",
            dependencies: ["KultrCore"]
        ),
    ]
)
