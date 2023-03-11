// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import os.log
import PackageDescription

// Process enviroment variables.
typealias EnviromentBool = (var: String, default: Bool)

// Possible keys for `env` and their default value
let USE_CARGO 		          = envBool(("USE_CARGO", 					false))
let USE_CXX_INTEROP           = envBool(("USE_CXX_INTEROP", 			false))
let USE_CXX_MODULES           = envBool(("USE_CXX_MODULES", 			false))
let INHIBIT_UPSTREAM_WARNINGS = envBool(("INHIBIT_UPSTREAM_WARNINGS", 	true))
let STATIC_LIBRARY            = envBool(("STATIC_LIBRARY", 				false))

let unsafe_flags: [String]    = INHIBIT_UPSTREAM_WARNINGS ? ["-w"] : [String]()

let unsafe_flags_cxx: [String] = INHIBIT_UPSTREAM_WARNINGS ? ["-w", "-Wno-module-import-in-extern-c"] : ["-Wno-module-import-in-extern-c"]

extension Package.Dependency {
	/// The combination of all the dependencies for the Package.
	enum SideStore {
		static let dependencies: [Package.Dependency] =
			Packages_SideStoreTeam +
			Packages_3rdParty +
			Plugins_BuildTools +
			Plugins_CICD
	}

	/// Side Store Team Packages
	static let Packages_SideStoreTeam: [Package.Dependency] = [
		.github("SideStore/AltSign", from: "1.0.3"),
		.github("SideStore/iMobileDevice.swift", from: "1.0.5"),
		.github("SideStore/SideKit", from: "0.1.0"),
		/// @JoeMatt updated fork for Riley's `Roxas`
		.github("JoeMatt/Roxas", from: "1.2.2"),
	]

	/// 3rd party Packages
	static let Packages_3rdParty: [Package.Dependency] = [
		.github("SwiftPackageIndex/SemanticVersion", from: "0.3.5"),
		.github("johnxnguyen/Down", branch: "master"),
		.github("kean/Nuke", from: "7.0.0"),
		.github("kishikawakatsumi/KeychainAccess", from: "4.2.0"),
		.github("microsoft/appcenter-sdk-apple", from: "4.2.0"),
		.github("sindresorhus/LaunchAtLogin", from: "5.0.0"),
	]

	static let Plugins_BuildTools: [Package.Dependency] = [
		// Plugins
		/// IntentBuilder for spm support of intents and Logger injection
		.github("JoeMatt/SwiftPMPlugins", from: "1.0.0"),

		 /// Generate swift files with git head info
		.github("elegantchaos/Versionator", from: "1.0.3").disable,

		 /// plists from .json, including Info.plist
		.github("elegantchaos/InfomaticPlugin", branch: "main").disable
	]-?

	static let Plugins_CICD: [Package.Dependency] = [
		/// Swiftlint
		.github("lukepistrol/SwiftLintPlugin", from: "0.2.2").disable,

		/// git secrets from env (for adding sensative api keys via CI/CD,
		/// ```sh
		/// swift package plugin --allow-writing-to-package-directory secret-keys generate
		/// ```
		/// or using Mint
		/// ```sh
		/// mint run secret-keys generate
		/// ```
		.github("simorgh3196/swift-secret-keys", from: "0.0.1").disable,

		/// #__ Swift docc generator __
		/// `swift package generate-documentation`
		/// ## Inline creation
		/// ```sh
		/// swift package \
		/// 	--allow-writing-to-directory ./docs \
		/// 	generate-documentation \
		/// 	--target MyFramework \
		/// 	--output-path ./docs
		/// ```
		/// ## Preview:
		/// `swift package --disable-sandbox preview-documentation --target MyFramework`
		/// [Hosting](https://apple.github.io/swift-docc-plugin/documentation/swiftdoccplugin/)
		.github("apple/swift-docc-plugin", from: "1.1.0").disable,
	]-?

	#if USE_RESULT_BUILDER
	// TODO: Make a DSL using a @resultBuilder
	@DependencyBuilder
	static var Additional_Plugins: [Package.Dependency] {
		// Secrets manager using `.env`
		github("vdka/SecretsManager.git", from: "1.0.0")

		// Generate `PackageBuild` struct with build time info about repo
		github("DimaRU/PackageBuildInfo", branch: "master")


		///  Plugin for simply updating your Package.swift file consistently and understandably.
		github("mackoj/PackageGeneratorPlugin", from: "0.3.0")
		/// Plugin for quickly updating your Schemes files
		github("mackoj/SchemeGeneratorPlugin", from: "0.5.5")
		github("pointfreeco/swift-composable-architecture", from: "0.45.0")
	}
	#else
	static let Additional_Plugins: [Package.Dependency] = [
		// Secrets manager using `.env`
		github("vdka/SecretsManager.git", from: "1.0.0").disable,

		// Generate `PackageBuild` struct with build time info about repo
		github("DimaRU/PackageBuildInfo", branch: "master").disable,

		/// Plugin for simply updating your `Package.swift` file consistently and understandably.
		github("mackoj/PackageGeneratorPlugin", from: "0.3.0").disable,

		/// Plugin for quickly updating your `.xcscheme` files
		github("mackoj/SchemeGeneratorPlugin", from: "0.5.5").disable,
		github("pointfreeco/swift-composable-architecture", from: "0.45.0").disable
	].removeNils()
	#endif
}

let InfomaticPlugin        : Target.PluginUsage = .plugin(name: "InfomaticPlugin", 		package: "InfomaticPlugin")
let PackageBuildInfoPlugin : Target.PluginUsage = .plugin(name: "PackageBuildInfoPlugin",package: "PackageBuildInfo")
let SafeURLPlugin          : Target.PluginUsage = .plugin(name: "SafeURLPlugin", 		package: "SafeURLPlugin")
let SecretsManagerPlugin   : Target.PluginUsage = .plugin(name: "SecretsManagerPlugin", package: "SecretsManager")
let VersionatorPlugin      : Target.PluginUsage = .plugin(name: "VersionatorPlugin", 	package: "Versionator")
let IntentBuilderPlugin    : Target.PluginUsage = .plugin(name: "IntentBuilderPlugin", 	package: "SwiftPMPlugins")
let LoggerPlugin           : Target.PluginUsage = .plugin(name: "LoggerPlugin",			package: "SwiftPMPlugins")

let commonPlugins: [Target.PluginUsage] = [LoggerPlugin]

// MARK: - 3rd Party Dependencies
let AppCenterAnalytics: Target.Dependency = .product(name: "AppCenterAnalytics", package: "appcenter-sdk-apple")
let AppCenterCrashes  : Target.Dependency = .product(name: "AppCenterCrashes", package: "appcenter-sdk-apple")
let CoreCrypto		: Target.Dependency = .product(name: "CoreCrypto", package: "AltSign")
let CCoreCrypto		: Target.Dependency = .product(name: "CCoreCrypto", package: "AltSign")
let libimobiledevice: Target.Dependency = .product(name: "libimobiledevice", package: "iMobileDevice.swift")
let Roxas			: Target.Dependency = .product(name: "Roxas", package: "Roxas")
let RoxasUI			: Target.Dependency = .product(name: "RoxasUI", package: "Roxas")

// MARK: - Linking
let frameworksCommon: [LinkerSetting] = [ "Avfoundation",
										  "CoreData",
										  "Combine",
										  "Network",
										  "UniformTypeIdentifiers" ].map{LinkerSetting.linkedFramework($0)}

let frameworksIOS: [LinkerSetting] = [
	"ARKit",
	"AudioToolbox",
	"AuthenticationServices",
	"CoreHaptics",
	"Intents",
	"IntentsUI",
	"MessageUI",
	"MobileCoreServices",
	"QuickLook",
	"SafariServices",
	"UserNotifications",
	"WidgetKit"
]
	.map{LinkerSetting.linkedFramework($0,
									   .when(platforms: [.iOS, .macCatalyst]))}

// MARK: -- PACKAGE --
let package = Package(
	name: "SideStore",
	defaultLocalization: "en",
	platforms: [
		.iOS(.v14),
		.tvOS(.v14),
		.macCatalyst(.v14),
		.macOS(.v12),
	],
	products: Product.products,
	dependencies: Package.Dependency.SideStore.dependencies,
	targets: Target.SideStore.targets,
	swiftLanguageVersions: [.v5],
	cLanguageStandard: .gnu11,
	cxxLanguageStandard: .gnucxx14
)

// ----------------
// MARK: - Products
// ----------------
extension Product {
	static let products: [Product] = [
		// Modules
		SideStoreAppKit.0,
		SideStoreAppKit.static,
		SideStoreAppKit.dynamic,

		SideStoreCore.0,
		SideStoreCore.static,
		SideStoreCore.dynamic,

		SideWidgetKit.0,
		SideWidgetKit.static,
		SideWidgetKit.dynamic,

		// `.app` Executables
		SideStore_app,
	] + cliProducts

	// CLI Executables
	#if HAVE_MACOS_DAEMON
	static let cliProducts: [Product] = [
		SideDaemon
	]
	#else
	static let cliProducts: [Product] = []
	#endif

	// SideStoreAppKit
	static let SideStoreAppKit = librarySet("SideStoreAppKit")

	// SideStoreCore
	static let SideStoreCore = librarySet("SideStoreCore")

	// SideWidgetKit
	static let SideWidgetKit = librarySet("SideWidgetKit")

	// SideStore Executable
	static let SideStore_app: Product 	= .executable( name: "SideStore", targets: ["SideStore"])

	#if HAVE_MACOS_DAEMON
	// SideDaemon Executable
	static let SideDaemon	: Product	= .executable(name: "SideDaemon", targets: ["SideDaemon"])
	#endif

	#if USE_CARGO_BUILD_PLUGIN
	// Cargo Plugin (WIP)
	static let CargoPlugin: Product = .plugin(name: "CargoPlugin", targets: ["CargoPlugin"])
	#endif
}


// ----------------
// MARK: - Targets
// ----------------

extension Target {
	enum SideStore { //: Encodable, CaseIterable {
		static let linkerSettings: [LinkerSetting] = frameworksCommon + frameworksIOS + [
			.linkedFramework("UIKit", .when(platforms: [.iOS, .macCatalyst, .tvOS])),
			.linkedLibrary("AppleArchive")
		]
	}
}
typealias TargetPair = (target: PackageDescription.Target, testTarget: PackageDescription.Target?)

// MARK: - SideStoreAppKit
extension Target.SideStore {

	/// All the targets fo be added to `Package(targets:)`
	static let targets: [Target] = publicTargets + Internal.targets + pluginTargets

	/// __Public Targets__
	static let publicTargets: [Target] = [
		// SideStoreAppKit
		SideStoreAppKit,

		// iOS Widget
		SideWidgetKit,

		// SideStoreCore
		SideStoreCore.target,
		SideStoreCore.testTarget,

		// SideBackup Executable
		SideBackup,

		// SidePatcher
		SidePatcher.target,
		SidePatcher.testTarget,

		// App Bundle
		Apps.SideStore_app,
	].compactMap{$0}

	#if HAVE_MACOS_DAEMON
	static let cliTargets: [Target] = [
		// SideDaemon
		SideDaemon.target,
		SideDaemon.testTarget,
	]
	#else
	static let cliTargets: [Target] = []
	#endif

	/// __PluginTargets__
	static let pluginTargets: [Target] = {
		Cargo.Plugins
	}()

	// MARK: - SideStoreAppKit
	static let SideStoreAppKit: Target =
		.target(
			name: "SideStoreAppKit",
			dependencies: [
				AppCenterAnalytics,
				AppCenterCrashes,
				"AltSign",
				"Down",
				"EmotionalDamage",
				"KeychainAccess",
				libimobiledevice,
				"MiniMuxer",
				"Nuke",
				Roxas,
				RoxasUI,
				"SideKit",
				"SidePatcher",
				"SideStoreCore",
			],
			resources: [],
			linkerSettings: linkerSettings,
			plugins: [LoggerPlugin, IntentBuilderPlugin]
		)

	// MARK: - SideWidgetKit
	static let SideWidgetKit: Target =
		.target(
			name: "SideWidgetKit",
			dependencies: [
				"SideKit",
				"SideStoreAppKit",
				"SideStoreCore"
			],
			plugins: commonPlugins
		)

	// MARK: - SideStoreCore
	static let SideStoreCore: TargetPair = (
		.target(
			name: "SideStoreCore",
			dependencies: [
				"AltSign",
				"KeychainAccess",
				Roxas,
				"SemanticVersion"],
			plugins: commonPlugins),
		.testTarget(
			name: "SideStoreCoreTests",
			dependencies: ["SideStoreCore", "KeychainAccess", "AltSign", "SemanticVersion", "SideKit"]))

#if HAVE_MACOS_DAEMON
	// MARK: - SideDaemon
	/// This is mostly leftover from `AltDaemon`
	/// We don't need or use it, but it felt bad to just delete it at the moment.
	static let SideDaemon: TargetPair = (
	        .executableTarget(
	            name: "SideDaemon",
	            dependencies: [
					"AltSign",
					"SideKit",
					CoreCrypto,
					CCoreCrypto,
					.product(name: "LaunchAtLogin", package: "LaunchAtLogin", condition: .when(platforms: [.macOS])),
				],
				plugins: commonPlugins
	        ),
	        .testTarget(name: "SideDaemonTests", dependencies: ["SideDaemon"]))
#endif

	// MARK: - SideBackup
	static let SideBackup: Target = .executableTarget(
		name: "SideBackup",
		dependencies: [
			"AltSign",
			"Roxas",
			"SideStoreCore",
			"SideKit"
		],
		exclude: [
			"Info.plist",
			"AltBackup.entitlements"]
			.map{ "Resources/\($0)" },
		resources: [
			.process("Resources/")
		],
		plugins: commonPlugins)

	// MARK: - SidePatcher
	/// Note: This is Objective-C so Swift generator's will fail if you try to apply them here - @JoeMatt
	static let SidePatcher: TargetPair = (
		.target(name: "SidePatcher", dependencies: [ RoxasUI ], plugins: []),
		.testTarget(name: "SidePatcherTests", dependencies: ["SidePatcher"]))
}

// MARK: -- .app Targets

/// This seems to be a new feature for XCode 14.3 beta.
/// `PackageDescription.ProductSetting` has no developer documentation
///  though there's probably info on swift-lang.org
extension Target.SideStore {
	// MARK: - SideStore.app
	enum Apps: Encodable, CaseIterable {
		case _apps(Target)

		static var allCases: [Apps] = [_apps(SideStore_app)]

		static let SideStore_app: Target = .executableTarget(
			name: "SideStore",
			dependencies: [ "SideStoreAppKit" ],
			exclude: [
				"Resources/AltBackup.ipa",
				"Resources/Info.info",
				"Resources/Info.plist",
				"Resources/SideStore.entitlements",
				"Resources/tempEnt.plist",
			],
			resources: [
				.copy("Resources/JSON/apps-alpha.json"),
				.copy("Resources/JSON/apps.json"),
				.process("Resources/Assets"),
				.process("Resources/Base.lproj"),
				.process("Resources/Settings.bundle"),
				.process("Resources/Sounds"),
				.process("Resources/Storyboards"),
				.process("Resources/XIB")
			],
			linkerSettings: linkerSettings,
			plugins: commonPlugins
		)

#if false
		static let productSettings: [PackageDescription.ProductSetting] = [
			.bundleIdentifier(""),
			.bundleVersion(""),
			.displayVersion(""),
			.teamIdentifier(""),
			.iOSAppInfo(
				.init(
					appIcon: .asset("AppIcon"),
					accentColor: .asset("SettingsHighlighted"),
					supportedDeviceFamilies: [.phone, .mac],
					supportedInterfaceOrientations: [
						.portrait,
						.landscapeLeft(.when(deviceFamilies: [.mac, .pad])),
						.landscapeRight(.when(deviceFamilies: [.mac, .pad]))
					],
					capabilities: [
						.appTransportSecurity(configuration:
								.init(

								)),
						.fileAccess(.userSelectedFiles, mode: .readOnly),
						.fileAccess(.downloadsFolder, mode: .readOnly),
						.incomingNetworkConnections(.when(deviceFamilies: [.mac, .pad, .phone])),
						.localNetwork(purposeString: "", bonjourServiceTypes: ["_altserver._tcp"]),
						.outgoingNetworkConnections(),
						//.bluetoothAlways(purposeString: ""),
						//.calendars(purposeString: ""),
						//.camera(purposeString: ""),
						//.contacts(purposeString: ""),
						//.faceID(purposeString: ""),
						//.locationAlwaysAndWhenInUse(purposeString: ""),
					],
					appCategory: .developerTools,
					additionalInfoPlistContentFilePath: "Resources/Info.info")
			)
		]
#endif
	}

}

// MARK: -- Internal Targets
extension Target.SideStore {
	enum Internal: Encodable, CaseIterable {
		static var allCases: [PackageDescription.Target.SideStore.Internal] = targets.map{._internal($0)}

		case _internal(Target)

		// MARK: Internal Targets
		static let targets: [Target] = [
			em_proxy_target,

			emotionalDamageTarget.target,
			emotionalDamageTarget.testTarget,

			minimuxer_target,

			miniMuxerSwiftTarget.target,
			miniMuxerSwiftTarget.testTarget
		].compactMap{$0}

		// MARK: em_proxy
		private static let em_proxy_target: Target = .binaryTarget(
				name: "em_proxy",
				url: "https://github.com/SideStore/em_proxy/releases/download/build/em_proxy.xcframework.zip",
				checksum: "79f90075b8ff2f47540a5bccf5fb7740905cda63463f833e2505256237df3c1b")

		// MARK: - EmotionalDamage (Swift)
		private static let emotionalDamageTarget: TargetPair = (
				.target(name: "EmotionalDamage", dependencies: ["em_proxy"]),
				.testTarget(name: "EmotionalDamageTests", dependencies: ["EmotionalDamage"]))

		// MARK: minimuxer
		private static let minimuxer_target: Target =
			.binaryTarget(name: "minimuxer",
						  url: "https://github.com/SideStore/minimuxer/releases/download/build/minimuxer.xcframework.zip",
						  checksum: "aa47182547b60f4f7560bdc0f25ea797c69419765003d16d5039c13b87930ed1")

		// MARK: MiniMuxer.Swift
		private static let miniMuxerSwiftTarget: TargetPair = (
				.target(name: "MiniMuxer", dependencies: ["minimuxer", libimobiledevice]),
				.testTarget(name: "MiniMuxerTests",
							dependencies: ["MiniMuxer", libimobiledevice]))
		}
}

// MARK: - Helpers

/// Utility function to test if a value of enviroment variable is a representation of `true`, as case-insensative word, letter or digit
/// - Parameter key: A key value from an enviroment variable
/// - Returns: `true` if `1`, "on", "true", or "yes" when `.lowercased()`, or `false` if "off", "false", 0, "no". `.lowercased()`
func envBool(_ key: EnviromentBool) -> Bool {
	guard let value = ProcessInfo.processInfo.environment[key.`var`]?.lowercased() else { return key.default }
	// We check for the opposite style string to be true
	// or return the default. That way a junk string will
	// always return the default.
	if key.default == true {
		// Check if a known 'false' type or return 'true'
		let falseValues = ["0", "off", "f", "false", "n", "no"]
		return !falseValues.contains(value)
	} else {
		let trueValues = ["1", "on", "t", "true", "y", "yes"]
		return trueValues.contains(value)
	}
}

/// Utility function to generate 3 of the same target with different types` {_, .static, .dynamic}`
/// - Parameter name: Name of your exported library. Must have target of same name.
/// - Returns: `[Product.Library, Product.Library.Static, Product.Library.Dynamic]`
func librarySet(_ name: String) -> (Product, `static`: Product, `dynamic`: Product) {(
	.library(name: name, targets: [name]),
	.library(name: "\(name)-Static", type: .static, targets: [name]),
	.library(name: "\(name)-Dynamic", type: .dynamic, targets: [name]))}

#if USE_CARGO_BUILD_PLUGIN
enum Cargo: Encodable {
	enum Dependencies: Encodable {case _dependencies([Package.Dependency])}
	enum Target: Encodable {case _target(Target, test: Target?)}
	enum Plugin: Encodable {case _plugin(Target)}

	static let Dependencies: Cargo.Dependencies = [
			.github("apple/swift-argument-parser.git", from: "1.0.3"),
			.github("apple/swift-package-manager.git", branch: "release/5.7"),
			.github("apple/swift-tools-support-core.git", branch: "release/5.7"),
		]

	static let Executable: (Cargo.Target, test: Cargo.Target?) = ._target(
		.executableTarget(
			name: "Cargo",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "SwiftPM-auto", package: "swift-package-manager"),
				.product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
			]),
			.testTarget(
				name: "CargoTests",
				dependencies: ["Cargo"],
				exclude: [
					"swiftlint",
					"xcframework"
				]
			))

	static let Plugins: [Cargo.Plugin] = [
			.plugin(
				name: "CargoPlugin",
				capability: .buildTool(),
				dependencies: [
					"Cargo"
				]
			),
			.plugin(
				name: "CargoPlugin-Generate",
				capability: .command(
					intent: .custom(
						verb: "generate-code-from-rust",
						description: "Creates .c code from your `rust` code"
					),
					permissions: [
						.writeToPackageDirectory(reason: "This command generates source code")
					]
				),
				dependencies: ["Cargo"]
			)].map{._plugin($0)}
}
#else
enum Cargo {
	static let Plugins: [Target] = []
}
#endif


extension PackageDescription.Package.Dependency {
	var disable: PackageDescription.Package.Dependency? { nil }

	static func github(_ repo: String,
					   from: Version) -> PackageDescription.Package.Dependency {
		.package(url: "https://github.com/\(repo).git", from: from)}

	static func github(_ repo: String,
					   exact: Version) -> PackageDescription.Package.Dependency {
		.package(url: "https://github.com/\(repo).git", exact: exact)}

	static func github(_ repo: String,
					   branch: String) -> PackageDescription.Package.Dependency {
		.package(url: "https://github.com/\(repo).git", branch: branch)}

	static func github(_ repo: String,
					   revision: String) -> PackageDescription.Package.Dependency {
		.package(url: "https://github.com/\(repo).git", revision: revision)}
}

/// `-?` Operator added as a quick way to `.compactMap{$0}` an
/// array that has optionals. In combination with adding `.disable` which returns `Self?`
/// as an easy way to disable packages from `Package.swift` since there are some limitions
/// 1. #if's can't be used in static array initiliziers, unless using ugly inline functions, and that kills
/// the Swift processor a lot.
/// The other option was to use a `@resultBuilder`, which I started below, to add some
/// synataic suger but probablly overkill honeslty.
/// - Author: @JoeMatt
postfix operator -?
extension Array where Element == Package.Dependency? {
	func removeNils() -> [Package.Dependency] { self.compactMap{$0} }

	static postfix func -? (array: Self) -> [Package.Dependency] { array.removeNils() }
}

extension Array where Element == Target? {
	func removeNils() -> [Target] { self.compactMap{$0} }
	static postfix func -? (array: Self) -> [Target] { array.removeNils() }
}

/// I'm a WIP as a less verbose way of merging array's of various`Target`s and `Dependency` lists
@resultBuilder
struct DependencyBuilder {
	typealias Component = [Package.Dependency]
	typealias Expression = Package.Dependency
	static func buildExpression(_ element: Expression) -> Component {
		return [element]
	}
	static func buildOptional(_ component: Component?) -> Component {
		guard let component = component else { return [] }
		return component
	}
	static func buildEither(first component: Component) -> Component {
		return component
	}
	static func buildEither(second component: Component) -> Component {
		return component
	}
	static func buildArray(_ components: [Component]) -> Component {
		return Array(components.joined())
	}
	static func buildBlock(_ components: Component...) -> Component {
		return Array(components.joined())
	}
}
