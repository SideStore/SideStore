//
//  Command+Options.swift
//  Cargo
//
//  Created by Joseph Mattiello on 02/28/23.
//  Copyright © 2023 Joseph Mattiello. All rights reserved.
//

import ArgumentParser
import PackageModel

extension Command {
    struct Options: ParsableArguments {
        // MARK: - Package Loading

        @Option(help: ArgumentHelp("The location of the Package", valueName: "directory"))
        var packagePath = "."

        // MARK: - Building

        @Option(help: ArgumentHelp("The location of the build/cache directory to use", valueName: "directory"))
        var buildPath = ".build"

        @Option(help: ArgumentHelp("Build with a specific configuration", valueName: "debug|release"))
        var configuration = PackageModel.BuildConfiguration.release

        @Flag(inversion: .prefixedNo, help: "Whether to clean before we build")
        var clean = true

        @Flag(inversion: .prefixedNo, help: "Whether to include debug symbols in the built XCFramework")
        var debugSymbols = true

        @Flag(help: "Prints the available products and targets")
        var listProducts = false

        @Option(help: "The path to a .xcconfig file that can be used to override Xcode build settings. Relative to the package path.")
        var xcconfig: String?

        @Flag(help: "Enables Library Evolution for the whole build stack. Normally we apply it only to the targets listed to be built to work around issues with projects that don't support it.")
        var stackEvolution: Bool = false

        @Option(help: ArgumentHelp("Arbitrary Xcode build settings that are passed directly to the `xcodebuild` invocation. Can be specified multiple times.", valueName: "NAME=VALUE"))
        var xcSetting: [BuildSetting] = []

        // MARK: - Output Options

        @Option(
            help: ArgumentHelp(
                "A list of platforms you want to build for. Can be specified multiple times."
                    + " Default is to build for all platforms supported in your Package.swift, or all Apple platforms (except for maccatalyst platform) if omitted",
                valueName: TargetPlatform.allCases.map { $0.rawValue }.joined(separator: "|")
            )
        )
        var platform: [TargetPlatform] = []

        @Option(help: ArgumentHelp("Where to place the compiled library", valueName: "directory"))
        var output = "."

        @Flag(help: .hidden)
        var githubAction: Bool = false

        // MARK: - Targets

        @Argument(help: "An optional list of products (or targets) to build. Defaults to building all `.library` products")
        var products: [String] = []
    }
}

// MARK: - ParsableArguments Extensions

extension PackageModel.BuildConfiguration: ExpressibleByArgument {}
