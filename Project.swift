import ProjectDescription

let project = Project(
    name: "SideStore",
    organizationName: "SideStore.io",
    targets: [
        Target(
            name: "SideStore",
            platform: .iOS,
            product: .app,
            bundleId: "com.SideStore.SideStore",
            infoPlist: "Info.plist",
            sources: ["SideStoreApp/Sources/SideStore/**"],
            resources: ["SideStoreApp/Sources/SideStore/Resources/**"],
            headers: .headers(
                public: [],
                private: [],
                project: []
            ),
			entitlements: "SideStoreApp/Sources/SideStore/Resources/SideStore.entitlements",
            dependencies: [
                .package(path: "SideStoreApp"),
				.target(name: "SideWidget"),
                .sdk(name: "libAppleAcrhive.tbd", status: .required)
            ],
			settings: .settings(configurations: [
				.debug(name: "Debug", xcconfig: "SideStoreApp/Configurations/SideStore-Debug.xcconfig"),
				.release(name: "Release", xcconfig: "SideStoreApp/Configurations/SideStore-Release.xcconfig"),
			])
        ),

          Target(
            name: "SideWidget",
            platform: .iOS,
            product: .appExtension,
            bundleId: "com.SideStore.SideStore.SideWidget",
            infoPlist: .extendingDefault(with: [
                "ALTAppGroups": [
                    "group.com.SideStore.SideStore",
                    "group.$(APP_GROUP_IDENTIFIER)",
                    ],
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService"
                ]
            ]),
			sources: ["SideStoreApp/Sources/SideWidget/**"],
			entitlements: "SideStoreApp/Sources/SideWidget/Resources/SideWidgetExtension.entitlements",
            dependencies: [
                .package(product: "Shared"),
                .package(product: "AltStoreCore")
            ]
        ),

// Target(
//     name: "SideStoreTests",
//     platform: .iOS,
//     product: .unitTests,
//     bundleId: "com.SideStore.SideStoreTests",
//     infoPlist: "Info.plist",
//     sources: ["SideStoreApp/Tests/SideStoreAppTests/**"],
//     dependencies: [
//         .target(name: "SideStore")
//     ]
// ),
//		Target(
//			name: "SideStore",
//			platform: .tvOS,
//			product: .app,
//			bundleId: "com.SideStore.SideStore",
//			infoPlist: "Info.plist",
//			sources: ["SideStoreApp/Sources/SideStoreTV/**"],
//			dependencies: [
//				.target(name: "TopShelfExtension"),
//			]
//		),
//		Target(
//			name: "TopShelfExtension",
//			platform: .tvOS,
//			product: .tvTopShelfExtension,
//			bundleId: "com.SideStore.SideStore.TopShelfExtension",
//			infoPlist: .extendingDefault(with: [
//				"CFBundleDisplayName": "$(PRODUCT_NAME)",
//				"NSExtension": [
//					"NSExtensionPointIdentifier": "com.apple.tv-top-shelf",
//					"NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ContentProvider",
//				],
//			]),
//			sources: "SideStoreApp/Sources/TopShelfExtension/**",
//			dependencies: [
//			]
//		),
    ]
)
