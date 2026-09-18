// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThubanCanvasCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThubanCanvasCore", targets: ["ThubanCanvasCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "ThubanCanvasCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThubanCanvasCoreTests",
            dependencies: ["ThubanCanvasCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
