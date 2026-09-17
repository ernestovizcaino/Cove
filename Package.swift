// swift-tools-version: 6.0
import PackageDescription

// Portable domain, connection editor state and catalog networking ONLY.
// Open Cove.xcodeproj to build the SwiftUI macOS application.
let package = Package(
    name: "CoveCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CoveCore", targets: ["CoveCore"])],
    targets: [
        .target(name: "CoveCore", path: "Cove", exclude: [
            "App", "Components", "Features/Chat", "Features/History", "Features/Settings",
            "Features/Connect/ConnectMenu.swift", "Features/Connect/ConnectionEditorView.swift",
            "Features/Connect/ModelPickerView.swift", "Infrastructure/Persistence", "Infrastructure/Security",
            "Infrastructure/AI/OllamaGenerationClient.swift", "Infrastructure/AI/SDKGenerationClient.swift",
            "Resources", "Info.plist", "Cove.entitlements"
        ], sources: ["Domain", "Features/Connect/ConnectionEditorStore.swift",
                     "Infrastructure/AI/ModelCatalogService.swift", "Infrastructure/AI/NetworkSession.swift"]),
        .testTarget(name: "CoveCoreTests", dependencies: ["CoveCore"], path: "Tests/CoreTests")
    ]
)
