// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hyperdash-usage-receiver",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "hyperdash-usage-receiver", targets: ["hyperdash-usage-receiver"]),
    ],
    targets: [
        .executableTarget(name: "hyperdash-usage-receiver"),
    ]
)
