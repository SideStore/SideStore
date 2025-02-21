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

private extension UITests {
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



private extension UITests {
    
    private func performBulkAddingRecommendedSources(for app: XCUIApplication) throws {
        // Navigate to the Sources screen and open the Add Source view.
        app.tabBars["Tab Bar"].buttons["Sources"].tap()
        app.navigationBars["Sources"].buttons["Add"].tap()
        
        let cellsQuery = app.collectionViews.cells
        
        // Data model for recommended sources. NOTE: This list order is required to be the same as that of "Add Source" Screen
        let recommendedSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("SideStore Team Picks\ncommunity-apps.sidestore.io/sidecommunity.json", "SideStore Team Picks", false),
            ("Provenance EMU\nprovenance-emu.com/apps.json", "Provenance EMU", false),
//            ("Countdown Respository\nneoarz.github.io/Countdown-App/Countdown.json", "Countdown Respository", false),
//            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", false),
//            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", true),
//            ("Flyinghead\nflyinghead.github.io/flycast-builds/altstore.json", "Flyinghead", false),
//            ("PojavLauncher Repository\nalt.crystall1ne.dev", "PojavLauncher Repository", true),
//            ("PokeMMO\npokemmo.eu/altstore/", "PokeMMO", false),
//            ("Odyssey\ntheodyssey.dev/altstore/odysseysource.json", "Odyssey", false),
//            ("Yattee\nrepos.yattee.stream/alt/apps.json", "Yattee", false),
//            ("ThatStella7922 Source\nThe home for all apps ThatStella7922", "ThatStella7922 Source", false)
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
