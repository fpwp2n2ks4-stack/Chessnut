// swift-tools-version: 5.9
// ChessnutAir — application macOS minimale : jouer exclusivement sur l'échiquier
// physique Chessnut (Bluetooth) contre un moteur UCI, avec choix de la cadence,
// des couleurs et du nombre de parties.

import PackageDescription

let package = Package(
    name: "ChessnutAir",
    defaultLocalization: "fr",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ChessnutAir",
            path: "Sources/ChessnutAir",
            resources: [.process("Resources")]
        )
    ]
)
