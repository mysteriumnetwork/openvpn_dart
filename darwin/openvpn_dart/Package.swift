// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "openvpn_dart",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0")
  ],
  products: [
    .library(name: "openvpn-dart", targets: ["openvpn_dart"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "openvpn_dart",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    )
  ]
)
