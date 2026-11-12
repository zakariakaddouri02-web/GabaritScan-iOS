// swift-tools-version: 5.9
// Package.swift — Utilisé pour l'éditeur VS Code (sourcekit-lsp).
// Le vrai build se fait via GabaritScan.xcodeproj sur Codemagic.
import PackageDescription

let package = Package(
    name: "GabaritScan",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "GabaritScan", targets: ["GabaritScan"])
    ],
    targets: [
        .target(
            name: "GabaritScanNative",
            path: "GabaritScan/Native",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("apriltag"),
                .headerSearchPath("apriltag/common"),
                .define("_USE_MATH_DEFINES"),
            ]
        ),
        .target(
            name: "GabaritScan",
            dependencies: ["GabaritScanNative"],
            path: "GabaritScan/Sources"
        )
    ]
)
