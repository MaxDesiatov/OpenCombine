// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "OpenCombine",
    products: [
        .library(name: "OpenCombine", targets: ["OpenCombine"]),
        .library(name: "OpenCombineDispatch", targets: ["OpenCombineDispatch"]),
        .library(name: "OpenCombineFoundation", targets: ["OpenCombineFoundation"]),
    ],
    targets: [
        .target(name: "COpenCombineHelpers"),
        .target(name: "OpenCombine", dependencies: [
            .target(name: "COpenCombineHelpers", .when(platforms: [.macOS, .linux, .iOS])
        ]),
        .target(name: "OpenCombineDispatch", dependencies: ["OpenCombine"]),
        .target(name: "OpenCombineFoundation", dependencies: ["OpenCombine",
                                                              "COpenCombineHelpers"]),
        .testTarget(name: "OpenCombineTests",
                    dependencies: ["OpenCombine",
                                   "OpenCombineDispatch",
                                   "OpenCombineFoundation"],
                    swiftSettings: [.unsafeFlags(["-enable-testing"])])
    ],
    cxxLanguageStandard: .cxx1z
)
