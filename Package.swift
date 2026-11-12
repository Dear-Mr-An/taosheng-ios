// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaoShengPolicies",
    platforms: [.macOS(.v12)],
    products: [.library(name: "TaoShengPolicies", targets: ["TaoShengPolicies"])],
    targets: [
        .target(name: "TaoShengPolicies", path: "TaoSheng/Core/Policies"),
        .testTarget(name: "TaoShengPoliciesTests", dependencies: ["TaoShengPolicies"], path: "Tests/Policies")
    ]
)
