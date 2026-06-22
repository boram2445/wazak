// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Wazak",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Wazak", targets: ["Wazak"])
    ],
    targets: [
        .executableTarget(
            name: "Wazak",
            path: "Sources/Wazak",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
