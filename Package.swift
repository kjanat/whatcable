// swift-tools-version: 5.9
import PackageDescription

// WhatCable builds two very different shapes depending on the host OS.
//
// macOS: the full product set — the SwiftUI/AppKit menu bar app (WhatCable),
// the WidgetKit-adjacent AppKit layer, the IOKit backend, the Pro plugins,
// and the CLI.
//
// Linux: there is no AppKit / IOKit / WidgetKit, so those targets are omitted
// entirely. Linux ships the platform-agnostic core, a sysfs-backed snapshot
// provider, the CLI, and a lightweight local-web GUI. A system-library shim
// (CSQLite) provides libsqlite3, which Apple SDKs expose as a built-in module
// but Linux does not. Package.swift itself is evaluated on the build host, so
// `#if os(...)` here selects the manifest for the platform being built.

#if os(macOS)

let package = Package(
    name: "WhatCable",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatCable", targets: ["WhatCable"]),
        .executable(name: "whatcable-cli", targets: ["WhatCableCLI"]),
        .library(name: "WhatCableCore", targets: ["WhatCableCore"]),
        .library(name: "WhatCableAppKit", targets: ["WhatCableAppKit"])
    ],
    targets: [
        .target(
            name: "WhatCableCore",
            path: "Sources/WhatCableCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "WhatCableDarwinBackend",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableDarwinBackend"
        ),
        .target(
            name: "WhatCableAppKit",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableAppKit"
        ),
        .target(
            name: "WhatCablePlugins",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit"],
            path: "Sources/WhatCablePlugins"
        ),
        .executableTarget(
            name: "WhatCable",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit", "WhatCablePlugins"],
            path: "Sources/WhatCable",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "WhatCableCLI",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend", "WhatCableAppKit", "WhatCablePlugins"],
            path: "Sources/WhatCableCLI"
        ),
        .testTarget(
            name: "WhatCableCoreTests",
            dependencies: ["WhatCableCore"],
            path: "Tests/WhatCableCoreTests"
        ),
        .testTarget(
            name: "WhatCableDarwinTests",
            dependencies: ["WhatCableCore", "WhatCable", "WhatCableDarwinBackend"],
            path: "Tests/WhatCableDarwinTests"
        )
    ]
)

#else

// Linux (and any other non-Apple platform).
let package = Package(
    name: "WhatCable",
    defaultLocalization: "en",
    products: [
        .executable(name: "whatcable-cli", targets: ["WhatCableCLI"]),
        .executable(name: "whatcable-gui", targets: ["WhatCableLinuxGUI"]),
        .library(name: "WhatCableCore", targets: ["WhatCableCore"]),
        .library(name: "WhatCableLinuxBackend", targets: ["WhatCableLinuxBackend"])
    ],
    targets: [
        // libsqlite3 system-library shim. Requires the SQLite dev headers:
        //   Debian/Ubuntu: apt-get install libsqlite3-dev
        //   Fedora:        dnf install sqlite-devel
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "WhatCableCore",
            dependencies: ["CSQLite"],
            path: "Sources/WhatCableCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "WhatCableLinuxBackend",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableLinuxBackend"
        ),
        .executableTarget(
            name: "WhatCableCLI",
            dependencies: ["WhatCableCore", "WhatCableLinuxBackend"],
            path: "Sources/WhatCableCLI"
        ),
        .executableTarget(
            name: "WhatCableLinuxGUI",
            dependencies: ["WhatCableCore", "WhatCableLinuxBackend"],
            path: "Sources/WhatCableLinuxGUI"
        ),
        .testTarget(
            name: "WhatCableCoreTests",
            dependencies: ["WhatCableCore"],
            path: "Tests/WhatCableCoreTests"
        )
    ]
)

#endif
