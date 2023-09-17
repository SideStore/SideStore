// swift-tools-version:5.6

import PackageDescription

// Version number can be found in Source/Danger/Danger.swift

// switch to false when release
let isDevelop = true

let devProducts: [Product] = isDevelop
    ? [
        .library(name: "DangerDeps", type: .dynamic, targets: ["Danger-Swift"])
    ] : []
let devDependencies: [Package.Dependency] = isDevelop
    ? [
        // .package(url: "https://github.com/shibapm/Komondor", from: "1.1.4"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.50.7"),
        .package(url: "https://github.com/Realm/SwiftLint", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.10.0"),
        // .package(url: "https://github.com/shibapm/Rocket", from: "1.2.1")
    ] : []
let devTargets: [Target] = isDevelop
    ? [
        .testTarget(name: "DangerTests",
                    dependencies: [
                        "Danger",
                        "DangerFixtures",
                        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
                    ]),
        .testTarget(name: "RunnerLibTests",
                    dependencies: [
                        "RunnerLib",
                        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
        ], exclude: ["__Snapshots__"]),
        .testTarget(name: "DangerDependenciesResolverTests",
                    dependencies: [
                        "DangerDependenciesResolver",
                        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
                    ],
                    exclude: ["__Snapshots__"]),
    ]
    : []

let package = Package(
    name: "danger-swift",
    products: [
        // .library(name: "DangerDeps[SideStore]", type: .dynamic, targets: ["DangerDependencies"]), // dev
		.library(name: "SideStore", targets: ["SideStore", "SideStore-ObjC"]),
		.library(name: "AltStoreCore", targets: ["AltStoreCore"]),
		.library(name: "libimobiledevice", targets: ["libimobiledevice"]),
		.library(name: "EmotionalDamage", targets: ["EmotionalDamage"]),
		.library(name: "minimuxer", targets: ["minimuxer"]),
    ],
        .library(name: "Danger", targets: ["Danger"]),
        .library(name: "DangerFixtures", targets: ["DangerFixtures"]),
        .executable(name: "danger-swift", targets: ["Runner"]),
    ] + devProducts,
    dependencies: [
        .package(url: "https://github.com/danger/swift.git", from: "3.0.0"), // dev
		.package(url: "https://github.com/SideStore/Roxas.git", branch: "swiftpm"),
        // Danger Plugins
        // .package(url: "https://github.com/username/DangerPlugin.git", from: "0.1.0") // dev
    ],
        .package(url: "https://github.com/shibapm/Logger", from: "0.1.0"),
        .package(url: "https://github.com/mxcl/Version", from: "2.0.1"),
        .package(name: "OctoKit", url: "https://github.com/nerdishbynature/octokit.swift", from: "0.12.0"),
    ] + devDependencies,
    targets: [
        // .target(name: "DangerDependencies", dependencies: ["Danger", "DangerPlugin"], path: "Dependencies/Danger"), // dev
		.target(name: "SideStore",
				dependencies: ["SideStore-ObjC", "AltStoreCore", "EmotionalDamage", "libimobiledevice", "minimuxer", "em_proxy"],
				path: "AltStore",
				exclude: ["Operations/Patch App/ALTAppPatcher.m"]),

		.target(name: "SideStore-ObjC",
				dependencies: ["Roxas"],
				path: "AltStore",
				sources: ["Operations/Patch App/ALTAppPatcher.m"],
				publicHeadersPath: "Operations/Patch App/"),

		.target(name: "AltStoreCore",
				dependencies: ["AltStoreCore-ObjC"],
				path: "AltStoreCore",
				exclude: [
					"Types/ALTAppPermission.m",
					"Types/ALTPatreonBenefitType.m",
					"Types/ALTSourceUserInfoKey.m"
				]),

		.target(name: "AltStoreCore-ObjC",
				dependencies: ["Roxas"],
				path: "AltStoreCore",
				sources: ["Types/ALTAppPermission.m", "Types/ALTPatreonBenefitType.m", "Types/ALTSourceUserInfoKey.m"],
				publicHeadersPath: "Types"),

		.target(name: "EmotionalDamage",
				dependencies: [""],
				path: "EmotionalDamage"),

		.target(name: "libimobiledevice",
				dependencies: [""],
				path: "Dependencies/libimobiledevice/src",
				publicHeadersPath: "Dependencies/libimobiledevice/include/libimobiledevice"),

		.binaryTarget(	name: "minimuxer",
						path: "Dependencies/minimuxer/target/release/minimuxer.xcframework"),

		.binaryTarget(	name: "em_proxy",
						path: "Dependencies/em_proxy/target/release/em_proxy.xcframework"),

		// 	name: "SideStore",
		// 	// dependencies: [
		// 	// 	.product(name: "RxSwift", package: "RxSwift")
		// 	// ],
		// 	path: "AltStore",
		// 	exclude: ["Info.plist", "*.m"],
		// 	cSettings: cSettings,
		// 	cxxSettings: cxxSettings),

		// .target(
		// 	name: "PVLibrary-ObjC",
		// 	// dependencies: [
		// 	// 	.product(name: "RxSwift", package: "RxSwift")
		// 	// ],
		// 	path: "PVLibrary",
		// 	exclude: ["Info.plist", "*.swift"],
		// 	cSettings: cSettings,
		// 	cxxSettings: cxxSettings),
    ]
        .target(name: "Danger-Swift", dependencies: ["Danger"], plugins: [.plugin(name: "SwiftLintPlugin", package: "SwiftLint")]),
        .target(name: "DangerShellExecutor"),
        .target(name: "DangerDependenciesResolver", dependencies: ["DangerShellExecutor", "Version", "Logger"]),
        .target(name: "Danger", dependencies: ["OctoKit", "Logger", "DangerShellExecutor"]),
        .target(name: "RunnerLib", dependencies: ["Logger", "DangerShellExecutor", "Version"]),
        .executableTarget(name: "Runner", dependencies: ["RunnerLib", "Logger", "DangerDependenciesResolver"]),
        .target(name: "DangerFixtures", dependencies: ["Danger"]),
    ] + devTargets
)

// #if canImport(PackageConfig)
//     import PackageConfig

//     let config = PackageConfiguration([
//         "komondor": [
//             "pre-push": "swift test",
//             "pre-commit": [
//                 "swift test",
//                 "swift test --generate-linuxmain",
//                 "swift run swiftformat .",
//                 "swift run swiftlint autocorrect --path Sources/",
//                 "git add ."
//             ]
//         ],
//         "rocket": [
//             "pre_release_checks": [
//                 "clean_git"
//             ],
//             "steps": [
//                 "Scripts/update_makefile.sh",
//                 "Scripts/update_danger_version.sh",
//                 "Scripts/update_changelog.sh",
//                 "Scripts/change_is_develop.sh false",
//                 "git_add",
//                 "commit",
//                 "tag",
//                 "push",
//                 "Scripts/change_is_develop.sh true",
//                 "git_add",
//                 ["commit": ["message": "Enable dev depdendencies"]],
//                 "push",
//                 "Scripts/create_homebrew_tap.sh"
//             ]
//         ]
//     ]).write()
// #endif

// let package = Package(
//   name: "SideStore",
//   platforms: [
//     .iOS(.v13),
//     .tvOS(.v13),
//   ],
//   products: [
//     .library(name: "DangerDeps[SideStore]", type: .dynamic, targets: ["DangerDependencies"])  // dev
//   ],
//   dependencies: [
//     .package(url: "https://github.com/danger/swift.git", from: "3.0.0")  // dev
//     // Danger Plugins
//     // .package(url: "https://github.com/username/DangerPlugin.git", from: "0.1.0") // dev
//   ],
//   targets: [
//     .target(name: "DangerDependencies", dependencies: ["Danger", "DangerPlugin"])  // dev
//     // 	name: "SideStore",
//     // 	// dependencies: [
//     // 	// 	.product(name: "RxSwift", package: "RxSwift")
//     // 	// ],
//     // 	path: "AltStore",
//     // 	exclude: ["Info.plist", "*.m"],
//     // 	cSettings: cSettings,
//     // 	cxxSettings: cxxSettings),

//     // .target(
//     // 	name: "PVLibrary-ObjC",
//     // 	// dependencies: [
//     // 	// 	.product(name: "RxSwift", package: "RxSwift")
//     // 	// ],
//     // 	path: "PVLibrary",
//     // 	exclude: ["Info.plist", "*.swift"],
//     // 	cSettings: cSettings,
//     // 	cxxSettings: cxxSettings),
//   ]
// )
