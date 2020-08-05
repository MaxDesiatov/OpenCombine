// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "OpenCombine",
    products: [
        .library(name: "OpenCombine", targets: ["OpenCombine"]),
        // .library(name: "OpenCombineDispatch", targets: ["OpenCombineDispatch"]),
        // .library(name: "OpenCombineFoundation", targets: ["OpenCombineFoundation"]),
    ],
    dependencies: [
      // Dependencies declare other packages that this package depends on.
      // .package(url: /* package url */, from: "1.0.0"),
      .package(url: "https://github.com/MaxDesiatov/Runtime.git", .branch("wasi-build-5.3")),
    ],
    targets: [
        // .target(name: "COpenCombineHelpers", cxxSettings: [.headerSearchPath(".")]),
        .target(name: "OpenCombine", dependencies: [
          // "COpenCombineHelpers", 
          "Runtime"
          ]),
        // .target(name: "OpenCombineDispatch", dependencies: ["OpenCombine"]),
        // .target(name: "OpenCombineFoundation", dependencies: ["OpenCombine",
        //                                                       "COpenCombineHelpers"]),
        .testTarget(name: "OpenCombineTests",
                    dependencies: ["OpenCombine",
                                  //  "OpenCombineDispatch",
                                  //  "OpenCombineFoundation"
                                   ],
                    swiftSettings: [.unsafeFlags(["-enable-testing"])])
    ],
    cxxLanguageStandard: .cxx14
)
