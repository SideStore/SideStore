import Foundation
import XCTest

final class CertificateDiagnosticsTests: XCTestCase {
    private let appName = "Example App"

    private func context(willResign: Bool = true, checked: String = "CERT_A",
                         installed: String? = nil, active: String? = "CERT_A",
                         override: String? = nil, portal: Set<String> = ["CERT_B"]) -> CertificateValidationContext {
        CertificateValidationContext(willResign: willResign, checkedCertificateSerial: checked,
                                     installedAppSerial: installed, activeCertificateSerial: active,
                                     overrideCertificateSerial: override, portalCertificateSerials: portal)
    }

    func testFreshInstallIdentifiesDefaultForRevokedAndExpiredCertificates() throws {
        for status: CertificateStatus in [.revoked, .expired] {
            let error = try XCTUnwrap(context().error(for: status, appName: appName, customTeam: nil))
            XCTAssertTrue(error.localizedDescription.contains("default local signing certificate selected to sign"))
            XCTAssertFalse(error.localizedDescription.contains("used to install"))
            XCTAssertFalse(error.localizedDescription.contains("existing signature"))
            XCTAssertFalse(error.localizedDescription.contains("CERT_A"))
            let details = try XCTUnwrap((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String)
            XCTAssertTrue(details.contains("checkedCertificateSerial: CERT_A"))
            XCTAssertTrue(details.contains("installedAppSerial: nil"))
            XCTAssertTrue(details.contains("checkedCertificatePresentOnPortal: false"))
            XCTAssertTrue(try XCTUnwrap(error.recoverySuggestion).contains("Use Activate"))
        }
    }

    func testOverrideIsReportedEvenWithValidDefault() throws {
        for status: CertificateStatus in [.revoked, .expired] {
            let diagnostic = context(installed: "CERT_B", active: "CERT_B", override: "CERT_A")
            let error = try XCTUnwrap(diagnostic.error(for: status, appName: appName, customTeam: nil))
            XCTAssertEqual(diagnostic.purpose, .appSpecificSigningIdentity)
            XCTAssertTrue(error.localizedDescription.contains("app-specific signing certificate selected to sign"))
            XCTAssertFalse(error.localizedDescription.contains("default local"))
            let recovery = try XCTUnwrap(error.recoverySuggestion)
            XCTAssertTrue(recovery.contains("Change Certificate"))
            XCTAssertTrue(recovery.contains("Changing only the default may leave the app-specific selection in use"))
            XCTAssertTrue(diagnostic.diagnosticDetails.contains("activeCertificateSerial: CERT_B"))
        }
        // Presence of an override, even if it matches the default, determines its role.
        XCTAssertEqual(context(override: "CERT_A").purpose, .appSpecificSigningIdentity)
    }

    func testVerificationDescribesCheckedBinaryRegardlessOfSigningSelection() throws {
        for status: CertificateStatus in [.revoked, .expired] {
            let diagnostic = context(willResign: false, installed: "CERT_A", active: "CERT_B", override: "CERT_B")
            let error = try XCTUnwrap(diagnostic.error(for: status, appName: appName, customTeam: nil))
            XCTAssertEqual(diagnostic.purpose, .existingSignature)
            XCTAssertTrue(error.localizedDescription.contains("existing signature"))
            XCTAssertFalse(error.localizedDescription.contains("selected to sign"))
            XCTAssertTrue(try XCTUnwrap(error.recoverySuggestion).contains("Before using Resign, check"))
            XCTAssertTrue(try XCTUnwrap(error.recoverySuggestion).contains("install over the existing app without deleting it first"))
        }
    }

    func testFailureStatusAndCodesRemainDistinct() throws {
        for diagnostic in [context(), context(override: "CERT_A"), context(willResign: false)] {
            for customTeam: String? in [nil, "CUSTOM_TEAM"] {
                let revoked = try XCTUnwrap(diagnostic.error(for: .revoked, appName: appName, customTeam: customTeam))
                let expired = try XCTUnwrap(diagnostic.error(for: .expired, appName: appName, customTeam: customTeam))
                XCTAssertTrue(revoked.localizedDescription.contains("has been revoked"))
                XCTAssertTrue(expired.localizedDescription.contains("has expired"))
                XCTAssertEqual((revoked as NSError).code, customTeam == nil ? 2 : 4)
                XCTAssertEqual((expired as NSError).code, customTeam == nil ? 1 : 3)
                XCTAssertEqual((revoked as NSError).domain, OperationError.errorDomain)
                XCTAssertTrue(((revoked as NSError).userInfo[NSDebugDescriptionErrorKey] as? String)?.contains("certificateValidationStatus: revoked") == true)
                XCTAssertTrue(((expired as NSError).userInfo[NSDebugDescriptionErrorKey] as? String)?.contains("certificateValidationStatus: expired") == true)
                if customTeam != nil {
                    let details = try XCTUnwrap((revoked as NSError).userInfo[NSDebugDescriptionErrorKey] as? String)
                    XCTAssertTrue(details.contains("checkedCertificateCustomTeam: CUSTOM_TEAM"))
                }
            }
        }
        // Compiler-derived codes captured from develop before changing associated values.
        XCTAssertEqual((OperationError.noInstalledApps as NSError).code, 26)
        XCTAssertEqual((OperationError.invalidParameters("test") as NSError).code, 8)
        XCTAssertEqual((OperationError.unknownUDID(reason: "test") as NSError).code, 25)
    }

    func testValidAndCrossTeamCertificatesDoNotBecomeDiagnosticFailures() {
        for diagnostic in [context(), context(override: "CERT_A"), context(willResign: false), context(portal: ["CERT_A"])] {
            for isCrossSigned in [false, true] {
                for customTeam: String? in [nil, "CUSTOM_TEAM"] {
                    XCTAssertNil(diagnostic.error(for: .valid(isCrossSigned: isCrossSigned), appName: appName, customTeam: customTeam))
                }
            }
        }
    }

    func testRecoveryRequiresChangingInvalidIdentityAndWarnsAboutDataLoss() throws {
        for diagnostic in [context(), context(override: "CERT_A"), context(willResign: false)] {
            for status: CertificateStatus in [.revoked, .expired] {
                let error = try XCTUnwrap(diagnostic.error(for: status, appName: appName, customTeam: nil))
                let recovery = try XCTUnwrap(error.recoverySuggestion)
                XCTAssertTrue(recovery.hasPrefix("Deleting the app does not repair the selected signing identity and can erase its local data."))
                XCTAssertTrue(recovery.contains("Settings → Advanced → Certificates"))
                XCTAssertTrue(recovery.contains("private key"))
                XCTAssertFalse(recovery.contains("Please re-sign or reinstall"))
                XCTAssertFalse(recovery.contains("sign out"))
                XCTAssertFalse(recovery.contains("delete the app"))
                if diagnostic.purpose != .existingSignature {
                    XCTAssertTrue(recovery.contains("Developer Portal alone is not enough"))
                    XCTAssertFalse(recovery.contains("Resign"))
                }
            }
        }
    }

    func testNSErrorRoundTripPreservesRecoveryAndDetailsForErrorLogAndAlerts() throws {
        let error = try XCTUnwrap(context().error(for: .revoked, appName: appName, customTeam: nil)) as NSError
        // AppManager's serialization sanitizer retains only NSSecureCoding userInfo values.
        XCTAssertTrue(error.userInfo.values.allSatisfy { $0 is NSSecureCoding })
        // LoggedError persists domain, code and userInfo, then reconstructs NSError.
        let archived = try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: archived))
        let logged = NSError(domain: restored.domain, code: restored.code, userInfo: restored.userInfo)
        XCTAssertEqual(logged.localizedDescription, error.localizedDescription)
        XCTAssertEqual(logged.localizedRecoverySuggestion, error.localizedRecoverySuggestion)
        XCTAssertEqual(logged.userInfo[CertificateValidationContext.purposeErrorKey] as? String, "defaultSigningIdentity")
        XCTAssertEqual(logged.userInfo[NSDebugDescriptionErrorKey] as? String, error.userInfo[NSDebugDescriptionErrorKey] as? String)
        let logText = [logged.localizedDescription, logged.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        XCTAssertEqual(CertificateValidationContext.message(for: logged), logText)
        XCTAssertEqual(CertificateValidationContext.message(for: logged, description: logged.localizedFailureReason), logText)
        XCTAssertTrue(logText.contains("can erase its local data"))
        XCTAssertFalse(logText.contains("CERT_A"))
    }

    func testWrappedErrorPreservesGuidance() throws {
        let error = try XCTUnwrap(context(override: "CERT_A").error(for: .expired, appName: appName, customTeam: nil)) as NSError
        var info = error.userInfo
        info[NSLocalizedFailureErrorKey] = "Unable to refresh App"
        let wrapped = ALTWrappedError(error: error, userInfo: info)
        let message = CertificateValidationContext.message(for: wrapped)
        XCTAssertTrue(message.contains("app-specific signing certificate"))
        XCTAssertTrue(message.contains("can erase its local data"))
        XCTAssertTrue(message.contains("Change Certificate"))
    }

    func testUnrelatedErrorPresentationIsUnchanged() {
        XCTAssertTrue((OperationError.invalidParameters("test") as NSError).userInfo.isEmpty)
        let error = NSError(domain: "Other", code: 1, userInfo: [NSLocalizedDescriptionKey: "Other failure", NSLocalizedRecoverySuggestionErrorKey: "Other recovery"])
        XCTAssertEqual(CertificateValidationContext.message(for: error), "Other failure")
    }
}
