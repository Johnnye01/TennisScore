// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CourtCall",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "CourtCore", targets: ["CourtCore"]),
        .library(name: "CourtSession", targets: ["CourtSession"])
    ],
    targets: [
        .target(name: "CourtCore"),
        .target(name: "CourtSession", dependencies: ["CourtCore"]),
        .testTarget(name: "CourtCoreTests", dependencies: ["CourtCore"]),
        .testTarget(name: "CourtSessionTests", dependencies: ["CourtSession", "CourtCore"])
    ]
)
