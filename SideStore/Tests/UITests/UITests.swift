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
    
    private static let APP_NAME = "SideStore"
    
    override func setUpWithError() throws {
        // ignore spotlight it it was shown
        Self.springboard_app.tap()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        Self.deleteMyApp()
        super.tearDown()
    }
   
    
//    @MainActor   // Xcode 16.2 bug: UITest Record Button Disabled with @MainActor, see: https://stackoverflow.com/a/79445950/11971304
    func testBulkAddRecommendedSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.waitForExistence(timeout: 0.2), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performBulkAddingRecommendedSources(for: app)
    }
    
    func testBulkAddInputSources() throws {
        
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.waitForExistence(timeout: 0.2), "Notifications alert did not appear")
        systemAlert.scrollViews.otherElements.buttons["Allow"].tap()
        
        // Do the actual validation
        try performBulkAddingInputSources(for: app)
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
    
    class func deleteMyApp() {
        XCUIApplication().terminate()
        dismissSpringboardAlerts()
        
//        XCUIDevice.shared.press(.home)
        springboard_app.swipeDown()
        
        let searchBar = spotlight_app.textFields["SpotlightSearchField"]
        searchBar.typeText(APP_NAME)

        // Rest of the deletion flow...
        let appIcon = spotlight_app.icons[APP_NAME]
        if appIcon.waitForExistence(timeout: 0.2) {
            appIcon.press(forDuration: 1)
            
            let deleteAppButton = spotlight_app.buttons["Delete App"]
            deleteAppButton.tap()
            
            let confirmDeleteButton = springboard_app.alerts["Delete “\(APP_NAME)”?"]
            confirmDeleteButton.scrollViews.otherElements.buttons["Delete"].tap()
        }
        searchBar.buttons["Clear text"].tap()
        springboard_app.tap()
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


// Test guts (definition)
private extension UITests {
    
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
        appsSidestoreIoTextField.tap()
        appsSidestoreIoTextField.tap()
        collectionViewsQuery.staticTexts["Paste"].tap()

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
        
        // Tap on each textInputSources source's "add" button.
        for source in textInputSources {
            let sourceButton = cellsQuery.otherElements
                .containing(.button, identifier: source.identifier)
                .children(matching: .button)[source.identifier]
//            let addButton = sourceButton.children(matching: .button).firstMatch
            let addButton = sourceButton.children(matching: .button)["add"]
            addButton.tap()
            if source.requiresSwipe {
                sourceButton.swipeUp(velocity: .slow)  // Swipe up if needed.
            }
        }
        
        // Commit the changes by tapping "Done".
        app.navigationBars["Add Source"].buttons["Done"].tap()
        
        // Accept each source addition via alert.
        for source in textInputSources {
            let alertIdentifier = "Would you like to add the source “\(source.alertTitle)”?"
            app.alerts[alertIdentifier]
                .scrollViews.otherElements.buttons["Add Source"]
                .tap()
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
            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", false),
            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", true),
            ("Flyinghead\nflyinghead.github.io/flycast-builds/altstore.json", "Flyinghead", false),
            ("PojavLauncher Repository\nalt.crystall1ne.dev", "PojavLauncher Repository", false),
            ("PokeMMO\npokemmo.eu/altstore/", "PokeMMO", false),
            ("Odyssey\ntheodyssey.dev/altstore/odysseysource.json", "Odyssey", false),
            ("Yattee\nrepos.yattee.stream/alt/apps.json", "Yattee", false),
            ("ThatStella7922 Source\nThe home for all apps ThatStella7922", "ThatStella7922 Source", false)
        ]
        
        // Tap on each recommended source's "add" button.
        for source in recommendedSources {
            let sourceButton = cellsQuery.otherElements
                .containing(.button, identifier: source.identifier)
                .children(matching: .button)[source.identifier]
            let addButton = sourceButton.children(matching: .button)["add"]
            addButton.tap()
            if source.requiresSwipe {
                sourceButton.swipeUp()  // Swipe up if needed.
            }
        }
        
        // Commit the changes by tapping "Done".
        app.navigationBars["Add Source"].buttons["Done"].tap()
        
        // Accept each source addition via alert.
        for source in recommendedSources {
            let alertIdentifier = "Would you like to add the source “\(source.alertTitle)”?"
            app.alerts[alertIdentifier]
                .scrollViews.otherElements.buttons["Add Source"]
                .tap()
        }
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
