// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hyperdash-insights",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "hyperdash-insights", targets: ["hyperdash-insights"]),
        .library(name: "HyperdashInsights", targets: ["HyperdashInsights"]),
    ],
    targets: [
        .target(name: "HyperdashInsights"),
        .executableTarget(
            name: "hyperdash-insights",
            dependencies: ["HyperdashInsights"]
        ),
        .testTarget(
            name: "HyperdashInsightsTests",
            dependencies: ["HyperdashInsights"]
        ),
    ]
)
