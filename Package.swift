// swift-tools-version: 6.2
import PackageDescription

// The app compiles these same Foundation-only files directly. No added dependencies.
let package = Package(
    name: "CardRecognitionCore",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [.library(name: "CardRecognitionCore", targets: ["CardRecognitionCore"])],
    targets: [
        .target(name: "CardRecognitionCore", path: "LiveTranscriber/CardRecognition/Core"),
        .testTarget(name: "CardRecognitionTests", dependencies: ["CardRecognitionCore"], path: "Tests/CardRecognitionTests")
    ]
)
