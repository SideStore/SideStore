import Foundation
import PackagePlugin

@main
struct CargoPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
		guard let sourceTarget = target as? SourceModuleTarget else {
			return []
		}
		return createBuildCommands(
			inputFiles: sourceTarget.sourceFiles(withSuffix: "toml").map(\.path),
			packageDirectory: context.package.directory,
			workingDirectory: context.pluginWorkDirectory,
			tool: try context.tool(named: "cargo")
		)
	}

	private func createBuildCommands(
		inputFiles: [Path],
		packageDirectory: Path,
		workingDirectory: Path,
		tool: PluginContext.Tool
	) -> [Command] {
		if inputFiles.isEmpty {
			// Don't lint anything if there are no Swift source files in this target
			return []
		}

		var arguments = [
			"build", "\(workingDirectory)"
		]

		// Manually look for configuration files, to avoid issues when the plugin does not execute our tool from the
		// package source directory.
		if let configuration = packageDirectory.firstConfigurationFileInParentDirectories() {
			arguments.append(contentsOf: ["--manifest-path", "\(configuration.string)"])
		}
		arguments += inputFiles.map(\.string)

		// We are not producing output files and this is needed only to not include cache files into bundle
		let outputFilesDirectory = workingDirectory.appending("Output")

		return [
			.prebuildCommand(
				displayName: "Cargo",
				executable: tool.path,
				arguments: arguments,
				outputFilesDirectory: outputFilesDirectory
			)
		]
	}
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension CargoPlugin: XcodeBuildToolPlugin {
	func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
		let inputFilePaths = target.inputFiles
			.filter { $0.type == .source && $0.path.extension == "toml" }
			.map(\.path)
		return createBuildCommands(
			inputFiles: inputFilePaths,
			packageDirectory: context.xcodeProject.directory,
			workingDirectory: context.pluginWorkDirectory,
			tool: try context.tool(named: "swiftlint")
		)
	}
}
#endif

#if os(Linux)
import Glibc
#else
import Darwin
#endif

extension Path {
	/// Scans the receiver, then all of its parents looking for a configuration file with the name ".swiftlint.yml".
	///
	/// - returns: Path to the configuration file, or nil if one cannot be found.
	func firstConfigurationFileInParentDirectories() -> Path? {
		let defaultConfigurationFileName = "Cargo.toml"
		let proposedDirectory = sequence(
			first: self,
			next: { path in
				guard path.stem.count > 1 else {
					// Check we're not at the root of this filesystem, as `removingLastComponent()`
					// will continually return the root from itself.
					return nil
				}

				return path.removingLastComponent()
			}
		).first { path in
			let potentialConfigurationFile = path.appending(subpath: defaultConfigurationFileName)
			return potentialConfigurationFile.isAccessible()
		}
		return proposedDirectory?.appending(subpath: defaultConfigurationFileName)
	}

	/// Safe way to check if the file is accessible from within the current process sandbox.
	private func isAccessible() -> Bool {
		let result = string.withCString { pointer in
			access(pointer, R_OK)
		}

		return result == 0
	}
}
