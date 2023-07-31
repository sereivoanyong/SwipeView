// swift-tools-version:5.8
import PackageDescription

let package = Package(
  name: "SwipeView",
  platforms: [
    .iOS(.v11)
  ],
  products: [
    .library(name: "SwipeView", targets: ["SwipeView"])
  ],
  targets: [
    .target(name: "SwipeView", path: "SwipeView", sources: ["SwipeView.swift"])
  ]
)
