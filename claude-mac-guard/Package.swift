// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeMacGuard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeMacGuardCore", targets: ["ClaudeMacGuardCore"]),
        .executable(name: "ClaudeMacGuard", targets: ["ClaudeMacGuard"]),
        .executable(name: "ClaudeMacGuardSelfTest", targets: ["ClaudeMacGuardSelfTest"])
    ],
    targets: [
        .target(
            name: "ClaudeMacGuardCore",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "ClaudeMacGuard",
            dependencies: ["ClaudeMacGuardCore"]
        ),
        .executableTarget(
            name: "ClaudeMacGuardSelfTest",
            dependencies: ["ClaudeMacGuardCore"]
        )
    ]
)
