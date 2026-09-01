// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LlamaCpp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "llama", targets: ["llama"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10742/llama-b10742-xcframework.zip",
            checksum: "61f1c63fb567cf93c44b2755da05e6c904a81720c8255e79f4df239b6ad5d13b"
        ),
    ]
)
