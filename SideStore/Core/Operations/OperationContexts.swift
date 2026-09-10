//
//  Contexts.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//


import Foundation
import CoreData
import Network
import SideSign


enum AlternateIconMode {
    case preserve
    case set(URL)
    case remove
}

fileprivate struct OperationStepItem {
    let step: any OperationStep
    let weight: Int64
    let maxReuse: Int
    let resetProgress: Bool
}

protocol WeightedOperationContext: AnyObject {
    func weightForFirstOccurrence(of step: some OperationStep) -> Int64?
    func weight(for step: some OperationStep, occurrenceNumber: Int) -> Int64?
    func consumeWeight(for step: some OperationStep) throws -> Int64
    func attachProgressSlot(for step: some OperationStep, childProgress: Progress, parentProgress: Progress) throws -> Bool
}

class OperationContext: WeightedOperationContext
{
    var error: Error?
    var dbBackgroundContext: NSManagedObjectContext
    var operationStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    private var stepItems: [OperationStepItem]
    private var currentIndex = 0
    private var remainingReuses: [Int: Int] = [:]
    private var stepProgressSlots: [Int: Progress] = [:]

    fileprivate init(stepItems: [OperationStepItem] = [], error: Error? = nil, dbBackgroundContext: NSManagedObjectContext)
    {
        self.stepItems = stepItems
        self.error = error
        self.dbBackgroundContext = dbBackgroundContext
        self.operationStartTime = CFAbsoluteTimeGetCurrent()
    }

    fileprivate init(context: OperationContext)
    {
        self.stepItems = context.stepItems
        self.currentIndex = context.currentIndex
        self.error = context.error
        self.dbBackgroundContext = context.dbBackgroundContext
        self.remainingReuses = context.remainingReuses
        self.stepProgressSlots = context.stepProgressSlots
        self.operationStartTime = context.operationStartTime
    }

    func weightForFirstOccurrence(of step: some OperationStep) -> Int64? {
        weight(for: step, occurrenceNumber: 1)
    }

    func weight(for step: some OperationStep, occurrenceNumber: Int) -> Int64? {
        guard let target = (step as Any) as? AnyHashable else {
            debugLog("[OperationContext] Failed to cast step '\(step)' to AnyHashable")
            return nil
        }
        var matchCount = 0
        for item in stepItems {
            if let itemTarget = (item.step as Any) as? AnyHashable, itemTarget == target {
                matchCount += 1
                if matchCount == occurrenceNumber {
                    return item.weight
                }
            }
        }
        verboseLog("[OperationContext] Weight not found for step '\(step)' (occurrence \(occurrenceNumber))")
        return nil
    }

    private func findIndex(for step: some OperationStep) -> Int? {
        guard let target = (step as Any) as? AnyHashable else { return nil }
        return stepItems.indices[currentIndex...].first(where: {
            guard let itemTarget = (stepItems[$0].step as Any) as? AnyHashable else { return false }
            return itemTarget == target
        })
    }

    @discardableResult
    func consumeWeight(for step: some OperationStep) throws -> Int64 {
        guard let index = findIndex(for: step) else {
            debugLog("[OperationContext] Failed to consume weight for step '\(step)' from index \(currentIndex)")
            throw OperationError.invalidParameters("Missing progress weight for step '\(step)' in steps list")
        }
        
        let item = stepItems[index]
        guard item.maxReuse > 0 else {
            debugLog("[OperationContext] Invalid maxReuse (\(item.maxReuse)) for step '\(step)'")
            throw OperationError.invalidParameters("Invalid maxReuse (\(item.maxReuse)) for step '\(step)' in steps list")
        }
        
        let remaining: Int
        if let existing = remainingReuses[index] {
            remaining = existing
        } else {
            remaining = item.maxReuse
            remainingReuses[index] = remaining
        }
        
        if remaining > 1 {
            remainingReuses[index] = remaining - 1
            return item.weight
        } else {
            // remaining is 1. Clear it completely from the map and advance currentIndex.
            remainingReuses[index] = nil
            currentIndex = index + 1
            purgeCompletedProgressSlots()
            return item.weight
        }
    }

    func attachProgressSlot(for step: some OperationStep, childProgress: Progress, parentProgress: Progress) throws -> Bool {
        guard let index = findIndex(for: step) else { return false }
        let item = stepItems[index]
        guard item.resetProgress else { return false }
        
        let slot: Progress
        if let existing = stepProgressSlots[index] {
            slot = existing
        } else {
            slot = Progress.discreteProgress(totalUnitCount: childProgress.totalUnitCount)
            parentProgress.addChild(slot, withPendingUnitCount: item.weight)
            stepProgressSlots[index] = slot
        }
        
        slot.completedUnitCount = 0
        slot.addChild(childProgress, withPendingUnitCount: childProgress.totalUnitCount)
        try consumeWeight(for: step)
        return true
    }

    private func purgeCompletedProgressSlots() {
        for slotIndex in stepProgressSlots.keys where slotIndex < currentIndex {
            stepProgressSlots[slotIndex] = nil
        }
    }
}

class StandaloneOperationContext: OperationContext
{
    let steps: [StandaloneExecutionStep]

    init(steps: [StandaloneExecutionStep], error: Error? = nil, dbBackgroundContext: NSManagedObjectContext)
    {
        self.steps = steps
        super.init(stepItems: steps.map { 
                OperationStepItem(
                    step: $0.step, 
                    weight: $0.weight, 
                    maxReuse: $0.maxReuse, 
                    resetProgress: $0.resetProgress
                ) 
            }, 
            error: error, 
            dbBackgroundContext: dbBackgroundContext
        )
    }

    init(context: StandaloneOperationContext)
    {
        self.steps = context.steps
        super.init(context: context)
    }
}

class PipelineOperationContext: OperationContext
{
    let pipelineSteps: [PipelineExecutionStep]
    let handler: PipelineExecutionHandler

    init(
        pipelineSteps: [PipelineExecutionStep],
        handler: PipelineExecutionHandler,
        error: Error? = nil,
        dbBackgroundContext: NSManagedObjectContext
    ) {
        self.pipelineSteps = pipelineSteps
        self.handler = handler
        super.init(stepItems: pipelineSteps.map { 
                OperationStepItem(
                    step: $0.step, 
                    weight: $0.weight, 
                    maxReuse: 1, 
                    resetProgress: false
                ) 
            }, 
            error: error, 
            dbBackgroundContext: dbBackgroundContext
        )
    }

    init(context: PipelineOperationContext)
    {
        self.pipelineSteps = context.pipelineSteps
        self.handler = context.handler
        super.init(context: context)
    }
}

final class SharedPipelineContext: @unchecked Sendable
{
    private let lock = NSLock()
    private var rawAppIDs: [ALTAppID]?
    private var rawAppGroups: [ALTAppGroup]?

    var appIDs: [ALTAppID]? {
        get { lock.withLock { rawAppIDs } }
        set { lock.withLock { rawAppIDs = newValue } }
    }

    var appGroups: [ALTAppGroup]? {
        get { lock.withLock { rawAppGroups } }
        set { lock.withLock { rawAppGroups = newValue } }
    }

    func appendAppID(_ appID: ALTAppID) {
        lock.withLock { rawAppIDs = (rawAppIDs ?? []) + [appID] }
    }

    func appendAppGroup(_ appGroup: ALTAppGroup) {
        lock.withLock { rawAppGroups = (rawAppGroups ?? []) + [appGroup] }
    }
}

class InstallAppOperationContext: PipelineOperationContext
{
    let bundleIdentifier: String
    var customBundleIdentifier: String?
    var targetAppBundle: ALTApplication?

    var provisioningProfiles: [String: ALTProvisioningProfile]?
    var appexBundleIds: [String: String]?
    var useMainProfile = false
    var isFinished = false

    var overrideSigningCertificate: ALTCertificate?
    let activeSigningCertificate: ALTCertificate?

    var targetSigningCertificate: ALTCertificate? {
        overrideSigningCertificate ?? activeSigningCertificate
    }

    var targetCertStatus: CertificateStatus?
    var appendTeamID: Bool = true

    let standaloneContext: StandaloneOperationContext
    var sharedContext: SharedPipelineContext?

    var targetBundleIdentifier: String { customBundleIdentifier ?? bundleIdentifier }

    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        catch { self.error = error }
        return temporaryDirectory
    }()

    var ipaURL: URL?
    var resignedAppBundle: ALTApplication?
    var installedApp: InstalledApp?
    var releaseTrack: ReleaseTrack?
    var additionalEntitlements: [ALTEntitlement: any Sendable] = [:]
    
    var beginInstallationHandler: ((InstalledApp) -> Void)?

    var alternateIconMode: AlternateIconMode = .preserve

    var alternateIconURL: URL? {
        switch self.alternateIconMode {
        case .set(let url):
            return url
        case .preserve:
            if let installedApp = self.installedApp, installedApp.hasAlternateIcon {
                return installedApp.alternateIconURL
            }
            return nil
        case .remove:
            return nil
        }
    }

    // Non-nil when installing from a source.
    @AsyncManaged
    var appVersion: AppVersion?

    override var error: Error? {
        get { localError ?? standaloneContext.error }
        set { localError = newValue
            if standaloneContext.error == nil
            {
                // Assign newValue to standaloneContext.error if the latter is nil.
                // This fixes some operations continuing even after an error has occured.
                standaloneContext.error = newValue
            }
        }
    }
    private var localError: Error?

    init(
        pipelineSteps: [PipelineExecutionStep],
        bundleIdentifier: String,
        standaloneContext: StandaloneOperationContext,
        sharedContext: SharedPipelineContext? = nil,
        handler: PipelineExecutionHandler,
        additionalEntitlements: [ALTEntitlement: any Sendable] = [:],
        activeSigningCertificate: ALTCertificate? = nil,
        overrideSigningCertificate: ALTCertificate? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.standaloneContext = standaloneContext
        self.sharedContext = sharedContext
        self.additionalEntitlements = additionalEntitlements
        self.activeSigningCertificate = activeSigningCertificate
        self.overrideSigningCertificate = overrideSigningCertificate
        super.init(
            pipelineSteps: pipelineSteps,
            handler: handler,
            error: nil,
            dbBackgroundContext: standaloneContext.dbBackgroundContext
        )
        self.operationStartTime = standaloneContext.operationStartTime
    }
}
