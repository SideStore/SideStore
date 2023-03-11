import ProjectDescription

let config = Config(
    compatibleXcodeVersions: [upToNextMajor("14.0")],
    swiftVersion: "5.4.0",
    generationOptions:  .options([
        xcodeProjectName: "SideStore-\(.projectName)",
        organizationName: "SideStore.io",
        developmentRegion: "en"
    ])
)