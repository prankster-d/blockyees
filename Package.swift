// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlockyeesCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "BlockyeesCore", targets: ["BlockyeesCore"])],
    targets: [
        .target(name: "BlockyeesCore", path: "app/Blockyees", sources: [
            "Domain/Notebook.swift", "Infrastructure/Persistence/NotebookRepository.swift"
        ]),
        .testTarget(name: "BlockyeesCoreTests", dependencies: ["BlockyeesCore"], path: "tests/Unit")
    ]
)
