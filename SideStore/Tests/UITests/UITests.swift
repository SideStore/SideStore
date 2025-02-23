//
//  UITests.swift
//  UITests
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import XCTest
import Foundation

final class UITests: XCTestCase {
    
    // Handle to the homescreen UI
    private static let springboard_app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private static let spotlight_app = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    
    private static let searchBar = spotlight_app.textFields["SpotlightSearchField"]

    private static let APP_NAME = "SideStore"
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
//        Self.dismissSpotlight()
//        Self.deleteMyApp()
        Self.deleteMyApp2()

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
   
    
//    @MainActor   // Xcode 16.2 bug: UITest Record Button Disabled with @MainActor, see: https://stackoverflow.com/a/79445950/11971304
    func testBulkAddRecommendedSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performBulkAddingRecommendedSources(for: app)
    }
    
    func testBulkAddInputSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performBulkAddingInputSources(for: app)
    }

    func testRepeatabilityForStagingInputSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performRepeatabilityForStagingInputSources(for: app)
    }

    func testRepeatabilityForStagingRecommendedSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performRepeatabilityForStagingRecommendedSources(for: app)
    }

    
//    @MainActor
//    func testLaunchPerformance() throws {
//        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
//            // This measures how long it takes to launch your application.
//            measure(metrics: [XCTApplicationLaunchMetric()]) {
//                XCUIApplication().launch()
//            }
//        }
//    }
}

// Helpers
private extension UITests {
    
    class func dismissSpotlight(){
        // ignore spotlight if it was shown
        if searchBar.exists {
            let clearButton = searchBar.buttons["Clear text"]
            if clearButton.exists{
                clearButton.tap()
            }
        }
        springboard_app.tap()
    }
    
    class func deleteMyApp() {
        XCUIApplication().terminate()
        dismissSpringboardAlerts()
        
//        XCUIDevice.shared.press(.home)
        springboard_app.swipeDown()
        
        let searchBar = Self.searchBar
        _ = searchBar.exists || searchBar.waitForExistence(timeout: 5)
        searchBar.typeText(APP_NAME)

        // Rest of the deletion flow...
        let appIcon = spotlight_app.icons[APP_NAME]
        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        if appIcon.exists || appIcon.waitForExistence(timeout: 5) {
            appIcon.press(forDuration: 1)
            
            let deleteAppButton = spotlight_app.buttons["Delete App"]
            _ = deleteAppButton.exists || deleteAppButton.waitForExistence(timeout: 5)
            deleteAppButton.tap()
            
            let confirmDeleteButton = springboard_app.alerts["Delete “\(APP_NAME)”?"]
            _ = confirmDeleteButton.exists || confirmDeleteButton.waitForExistence(timeout: 5)
            confirmDeleteButton.scrollViews.otherElements.buttons["Delete"].tap()
        }
        
        let clearButton = searchBar.buttons["Clear text"]
        _ = clearButton.exists || clearButton.waitForExistence(timeout: 5)
        clearButton.tap()
        
        springboard_app.tap()
    }
    
    class func deleteMyApp2() {
        XCUIApplication().terminate()
        dismissSpringboardAlerts()
        
        // Rest of the deletion flow...
        let appIcon = springboard_app.icons[APP_NAME]
        // if it exists keep going immediately else wait for upto 5 sec with polling every 1 sec for existence
        if appIcon.exists || appIcon.waitForExistence(timeout: 5) {
            appIcon.press(forDuration: 1)
            
            do {
                let button = springboard_app.buttons["Remove App"]
                _ = button.exists || button.waitForExistence(timeout: 5)
                button.tap()
            }
            do {
                let button = springboard_app.buttons["Delete App"]
                _ = button.waitForExistence(timeout: 0.3)
                button.tap()
            }
            do {
                let button = springboard_app.buttons["Delete"]
                _ = button.waitForExistence(timeout: 0.3)
                button.tap()
            }

//            // Press home once to make the icons stop wiggling
//            XCUIDevice.shared.press(.home)
        }
    }
    
    
    
    class func dismissSpringboardAlerts() {
        for alert in springboard_app.alerts.allElementsBoundByIndex {
            if alert.exists {
                // If there's a "Cancel" button, tap it; otherwise, tap the first button.
                if alert.buttons["Cancel"].exists {
                    alert.buttons["Cancel"].tap()
                } else if let firstButton = alert.buttons.allElementsBoundByIndex.first {
                    firstButton.tap()
                }
            }
        }
    }
}


struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        // A basic LCG (not cryptographically secure, but fine for testing)
        seed = 6364136223846793005 &* seed &+ 1
        return seed
    }
}


// Test guts (definition)
private extension UITests {
    
    
    private func performBulkAdd(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery
    ) throws {
        
        // Tap on each sourceMappings source's "add" button.
        try tapAddForThesePickedSources(app: app, sourceMappings: sourceMappings, cellsQuery: cellsQuery)
        
        // Commit the changes by tapping "Done".
        app.navigationBars["Add Source"].buttons["Done"].tap()
        
        // Accept each source addition via alert.
        for source in sourceMappings {
            let alertIdentifier = "Would you like to add the source “\(source.alertTitle)”?"
            let addSourceButton = app.alerts[alertIdentifier]
                .scrollViews.otherElements.buttons["Add Source"]
            _ = addSourceButton.exists || addSourceButton.waitForExistence(timeout: 0.3)
            addSourceButton.tap()
        }
    }
    
    
    
    private func performBulkAddingInputSources(for app: XCUIApplication) throws {
        
        // set content into clipboard (for bulk add (paste))
        // NOTE: THIS IS AN ORDERED SEQUENCE AND MUST MATCH THE ORDER in textInputSources BELOW (Remember to take this into account when adding more entries)
        UIPasteboard.general.string = """
            https://alts.lao.sb
            https://taurine.app/altstore/taurinestore.json
            https://randomblock1.com/altstore/apps.json
            https://burritosoftware.github.io/altstore/channels/burritosource.json
            https://bit.ly/40Isul6
            https://bit.ly/wuxuslibraryplus
            https://bit.ly/Quantumsource-plus
            https://bit.ly/Altstore-complete
            https://bit.ly/Quantumsource
        """.trimmedIndentation
        
        let app = XCUIApplication()
        app.tabBars["Tab Bar"].buttons["Sources"].tap()
        app.navigationBars["Sources"].buttons["Add"].tap()

        let collectionViewsQuery = app.collectionViews
        let appsSidestoreIoTextField = collectionViewsQuery.textFields["apps.sidestore.io"]
        _ = appsSidestoreIoTextField.exists || appsSidestoreIoTextField.waitForExistence(timeout: 5)
        appsSidestoreIoTextField.tap()
        appsSidestoreIoTextField.tap()
        collectionViewsQuery.staticTexts["Paste"].tap()

//        if app.keyboards.buttons["Return"].exists {
//            app.keyboards.buttons["Return"].tap()
//        } else if app.keyboards.buttons["Done"].exists {
//            app.keyboards.buttons["Done"].tap()
//        } else {
//            // if still exists try tapping outside of text field focus
//            app.tap()
//        }
        
        if app.keyboards.count > 0 {
            appsSidestoreIoTextField.typeText("\n") // Fallback to newline so that soft kb is dismissed
        }
        
        let cellsQuery = collectionViewsQuery.cells

        // Data model for recommended sources. NOTE: This list order is required to be the same as that of "Add Source" Screen
        let textInputSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("Laoalts\nalts.lao.sb", "Laoalts", false),
            ("Taurine\ntaurine.app/altstore/taurinestore.json", "Taurine", false),
            ("RandomSource\nrandomblock1.com/altstore/apps.json", "RandomSource", false),
            ("Burrito's AltStore\nburritosoftware.github.io/altstore/channels/burritosource.json", "Burrito's AltStore", true),
            ("Qn_'s AltStore Repo\nbit.ly/40Isul6", "Qn_'s AltStore Repo", false),
            ("WuXu's Library++\nThe Most Up-To-Date IPA Library on AltStore.", "WuXu's Library++", false),
            ("Quantum Source++\nContains tweaked apps, free streaming, cracked apps, and more.", "Quantum Source++", false),
            ("AltStore Complete\nContains tweaked apps, free streaming, cracked apps, and more.", "AltStore Complete", false),
            ("Quantum Source\nContains all of your favorite emulators, games, jailbreaks, utilities, and more.", "Quantum Source", false),
        ]
        
        try performBulkAdd(app: app, sourceMappings: textInputSources, cellsQuery: cellsQuery)
    }
    
    
    private func performRepeatabilityForStagingInputSources(for app: XCUIApplication) throws {
        
        // set content into clipboard (for bulk add (paste))
        // NOTE: THIS IS AN ORDERED SEQUENCE AND MUST MATCH THE ORDER in textInputSources BELOW (Remember to take this into account when adding more entries)
        UIPasteboard.general.string = """
            https://alts.lao.sb
            https://taurine.app/altstore/taurinestore.json
            https://randomblock1.com/altstore/apps.json
            https://burritosoftware.github.io/altstore/channels/burritosource.json
            https://bit.ly/40Isul6
        """.trimmedIndentation
        
        let app = XCUIApplication()
        app.tabBars["Tab Bar"].buttons["Sources"].tap()
        app.navigationBars["Sources"].buttons["Add"].tap()

        let collectionViewsQuery = app.collectionViews
        let appsSidestoreIoTextField = collectionViewsQuery.textFields["apps.sidestore.io"]
        _ = appsSidestoreIoTextField.exists || appsSidestoreIoTextField.waitForExistence(timeout: 5)
        appsSidestoreIoTextField.tap()
        appsSidestoreIoTextField.tap()
        _ = appsSidestoreIoTextField.exists || appsSidestoreIoTextField.waitForExistence(timeout: 5)
        collectionViewsQuery.staticTexts["Paste"].tap()
        
        if app.keyboards.count > 0 {
            appsSidestoreIoTextField.typeText("\n") // Fallback to newline so that soft kb is dismissed
        }
        
        let cellsQuery = collectionViewsQuery.cells

        // Data model for recommended sources. NOTE: This list order is required to be the same as that of "Add Source" Screen
        let textInputSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("Laoalts\nalts.lao.sb", "Laoalts", false),
            ("Taurine\ntaurine.app/altstore/taurinestore.json", "Taurine", false),
            ("RandomSource\nrandomblock1.com/altstore/apps.json", "RandomSource", false),
            ("Burrito's AltStore\nburritosoftware.github.io/altstore/channels/burritosource.json", "Burrito's AltStore", false),
            ("Qn_'s AltStore Repo\nbit.ly/40Isul6", "Qn_'s AltStore Repo", false),
        ]
        
        let repeatCount = 3                                     // number of times to run the entire sequence
        let timeSeed = UInt64(Date().timeIntervalSince1970)     // time is unique (upto microseconds) - uncomment this to use non-deterministic seed based RNG (random number generator)

        try repeatabilityTest(app: app, sourceMappings: textInputSources, cellsQuery: cellsQuery, repeatCount: repeatCount, seed: timeSeed)
    }
    
    private func repeatabilityTest(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery,
        repeatCount: Int = 1,   // number of times to run the entire sequence
        seed: UInt64 = 42       // default = fixed seed for deterministic start of this generator
    ) throws {
        let seededGenerator = SeededGenerator(seed: seed)

        for _ in 0..<repeatCount {
            // The same fixed seeded generator will yield the same permutation if not advanced, so you might want to reinitialize or use a fresh copy for each iteration:
            var seededGenerator = seededGenerator                                       // uncomment this for repeats to use same(shuffled once due to inital seed) order for all repeats

//            let sourceMappings = sourceMappings.shuffled()                              // use this for non-deterministic shuffling
            let sourceMappings = sourceMappings.shuffled(using: &seededGenerator)       // use this for deterministic shuffling based on seed
            try tapAddForThesePickedSources(app: app, sourceMappings: sourceMappings, cellsQuery: cellsQuery)
        }
        
    }
    
    private func tapAddForThesePickedSources(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery
    ) throws {
        
        // Tap on each sourceMappings source's "add" button.
        for source in sourceMappings {
            let sourceButton = cellsQuery.otherElements
                .containing(.button, identifier: source.identifier)
                .children(matching: .button)[source.identifier]
            XCTAssert(sourceButton.exists || sourceButton.waitForExistence(timeout: 10), "Source preview for id: '\(source.alertTitle)' not found in the view")
            
//            let addButton = sourceButton.children(matching: .button).firstMatch
            let addButton = sourceButton.children(matching: .button)["add"]
            XCTAssert(addButton.exists || addButton.waitForExistence(timeout: 0.3), " `+` button for id: '\(source.alertTitle)' not found in the preview container")
            addButton.tap()
            
            if source.requiresSwipe {
                sourceButton.swipeUp(velocity: .slow)  // Swipe up if needed.
            }
        }
    }

    private func performBulkAddingRecommendedSources(for app: XCUIApplication) throws {
        // Navigate to the Sources screen and open the Add Source view.
        app.tabBars["Tab Bar"].buttons["Sources"].tap()
        app.navigationBars["Sources"].buttons["Add"].tap()
        
        let cellsQuery = app.collectionViews.cells
        
        // Data model for recommended sources. NOTE: This list order is required to be the same as that of "Add Source" Screen
        let recommendedSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("SideStore Team Picks\ncommunity-apps.sidestore.io/sidecommunity.json", "SideStore Team Picks", false),
            ("Provenance EMU\nprovenance-emu.com/apps.json", "Provenance EMU", false),
            ("Countdown Respository\nneoarz.github.io/Countdown-App/Countdown.json", "Countdown Respository", false),
            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", true),
            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", false),
            ("Flyinghead\nflyinghead.github.io/flycast-builds/altstore.json", "Flyinghead", false),
//            ("PojavLauncher Repository\nalt.crystall1ne.dev", "PojavLauncher Repository", false),            // not a stable source, sometimes becomes unreachable, so disabled
            ("PokeMMO\npokemmo.eu/altstore/", "PokeMMO", true),
            ("Odyssey\ntheodyssey.dev/altstore/odysseysource.json", "Odyssey", false),
            ("Yattee\nrepos.yattee.stream/alt/apps.json", "Yattee", false),
            ("ThatStella7922 Source\nThe home for all apps ThatStella7922", "ThatStella7922 Source", false)
        ]
        
        try performBulkAdd(app: app, sourceMappings: recommendedSources, cellsQuery: cellsQuery)
    }
    
    private func performRepeatabilityForStagingRecommendedSources(for app: XCUIApplication) throws {
        // Navigate to the Sources screen and open the Add Source view.
        app.tabBars["Tab Bar"].buttons["Sources"].tap()
        app.navigationBars["Sources"].buttons["Add"].tap()
        
        let cellsQuery = app.collectionViews.cells
        
        // Data model for recommended sources. NOTE: This list order is required to be the same as that of "Add Source" Screen
        let recommendedSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("SideStore Team Picks\ncommunity-apps.sidestore.io/sidecommunity.json", "SideStore Team Picks", false),
            ("Provenance EMU\nprovenance-emu.com/apps.json", "Provenance EMU", false),
            ("Countdown Respository\nneoarz.github.io/Countdown-App/Countdown.json", "Countdown Respository", false),
            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", false),
            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", false),
        ]
        
        let repeatCount = 3                                     // number of times to run the entire sequence
        let timeSeed = UInt64(Date().timeIntervalSince1970)     // time is unique (upto microseconds) - uncomment this to use non-deterministic seed based RNG (random number generator)

        try repeatabilityTest(app: app, sourceMappings: recommendedSources, cellsQuery: cellsQuery, repeatCount: repeatCount, seed: timeSeed)
    }
}





extension String {
    var trimmedIndentation: String {
        let lines = self.split(separator: "\n", omittingEmptySubsequences: false)
        let minIndent = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } // Ignore empty lines
            .map { $0.prefix { $0.isWhitespace }.count }
            .min() ?? 0
        
        return lines.map { line in
            String(line.dropFirst(minIndent))
        }.joined(separator: "\n")
    }
}
