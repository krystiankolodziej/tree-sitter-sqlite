// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TreeSitterSqlite",
    products: [
        .library(name: "TreeSitterSqlite", targets: ["TreeSitterSqlite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "TreeSitterSqlite",
            dependencies: [],
            path: ".",
            sources: ["src/parser.c"],
            publicHeadersPath: "bindings/swift/TreeSitterSqlite",
            cSettings: [
                .headerSearchPath("src"),
            ]
        ),
        .testTarget(
            name: "TreeSitterSqliteTests",
            dependencies: [
                "TreeSitterSqlite",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ],
            path: "bindings/swift/TreeSitterSqliteTests"
        ),
    ]
)
