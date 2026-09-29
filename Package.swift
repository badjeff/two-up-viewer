// swift-tools-version:5.9

// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "two-up-viewer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "two-up-viewer",
            path: "Sources/two-up-viewer",
            exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/two-up-viewer/Info.plist",
            ])]
        )
    ]
)
