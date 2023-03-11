import ArgumentParser
import Foundation

@main
struct Cargo: AsyncParsableCommand {
    static let configuration: CommandConfiguration = {
        if let directory = ProcessInfo.processInfo.environment["BUILD_WORKSPACE_DIRECTORY"] {
            FileManager.default.changeCurrentDirectoryPath(directory)
        }

        return CommandConfiguration(
            commandName: "cargo",
            abstract: "A tool to build `rust` projects with `cargo`.",
            version: Version.value,
            subcommands: [
                Build.self,
                Version.self
            ],
            defaultSubcommand: Build.self
        )
    }()
}
