// swift-tools-version: 6.0
import Foundation
import PackageDescription

let linkBuild = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent(".build")
let linkHeaders = linkBuild.appendingPathComponent("ableton-link/extensions/abl_link/include").path
let linkLibrary = linkBuild.appendingPathComponent("link-build/libabl_link.a").path

let package = Package(
    name: "Middy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Middy", targets: ["Middy"])],
    targets: [
        .systemLibrary(name: "AbletonLink"),
        .target(name: "MiddyCore"),
        .executableTarget(
            name: "Middy",
            dependencies: ["MiddyCore", "AbletonLink"],
            swiftSettings: [.unsafeFlags(["-Xcc", "-I\(linkHeaders)"])],
            linkerSettings: [.linkedLibrary("c++"), .unsafeFlags([linkLibrary])]
        ),
        .testTarget(name: "MiddyCoreTests", dependencies: ["MiddyCore"])
    ]
)
