import ArgumentParser
import SwiftLintFramework
import os.log

extension SwiftLint {
    struct Version: ParsableCommand {
        @Flag(help: "Display full version info")
        var verbose = false

        static let configuration = CommandConfiguration(abstract: "Display the current version of SwiftLint")

        static var value: String { SwiftLintFramework.Version.current.value }

        func run() throws {
            if verbose, let buildID = ExecutableInfo.buildID {
                os_log("Version: %@", type: .info , Self.value)
                os_log("Build ID: %@", type: .info , buildID)
            } else {
                print(Self.value)
            }
            ExitHelper.successfullyExit()
        }
    }
}
