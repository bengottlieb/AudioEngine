// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AudioEngine",
     platforms: [
              .macOS(.v10_15),
              .iOS(.v14),
              .watchOS(.v6)
         ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "AudioEngine",
            targets: ["AudioEngine"]),
    ],
    dependencies: [
		.package(url: "https://github.com/ios-tooling/Suite.git", from: "1.1.17"),
		.package(url: "https://github.com/ios-tooling/Convey.git", from: "3.0.9"),

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
		.target(name: "AudioEngine", dependencies: ["Suite", "Convey"]),
        
       // .testTarget(name: "AudioEngineTests", dependencies: ["AudioEngine"]),
    ]
)
