import DangerSwiftCoverage // package: https://github.com/f-meloni/danger-swift-coverage.git
import DangerSwiftLint // package: https://github.com/ashfurrow/danger-swiftlint.git
import DangerXCodeSummary // package: https://github.com/f-meloni/danger-swift-xcodesummary.git

let danger = Danger()

// swift run danger-swift [ci, pr] --dangerfile ./Dangerfile.swift
// xcodebuild test -scheme DangerSwiftCoverage-Package -derivedDataPath Build/ -enableCodeCoverage YES
// (Recommended) Cache the ~/.danger-swift folder

Coverage.xcodeBuildCoverage(.derivedDataFolder("Build"), 
                            minimumCoverage: 50, 
                            excludedTargets: ["DangerSwiftCoverageTests.xctest"])

SwiftLint.lint(directory: "SideStoreApp", configFile: ".swiftlint.yml")
