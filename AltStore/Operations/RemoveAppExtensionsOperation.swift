//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import Roxas
import AltSign

@objc(RemoveAppExtensionsOperation)
final class RemoveAppExtensionsOperation: ResultOperation<Void>
{
    let context: AppOperationContext
    let appInDatabase: AppProtocol
    
    init(context: AppOperationContext, appInDatabase: AppProtocol)
    {
        self.context = context
        self.appInDatabase = appInDatabase
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let targetAppBundle = context.app else {
            return self.finish(.failure(
                OperationError.invalidParameters("RemoveAppExtensionsOperation: context.app is nil")
            ))
        }
        
        
        self.removeAppExtensions(from: targetAppBundle,
                                  appInDatabase: appInDatabase as? ALTApplication,
                                  extensions: targetAppBundle.appExtensions,
                                  context.authenticatedContext.presentingViewController)
        
    }
    
    
    private static func removeExtensions(from extensions: Set<ALTApplication>) throws {
        for appExtension in extensions {
            print("Deleting extension \(appExtension.bundleIdentifier)")
            try FileManager.default.removeItem(at: appExtension.fileURL)
        }
    }
                                  
    
    
    private func removeAppExtensions(from targetAppBundle: ALTApplication,
                                     appInDatabase: ALTApplication?,
                                     extensions: Set<ALTApplication>,
                                     _ presentingViewController: UIViewController?)
    {
            
        // target App Bundle doesn't contain extensions so don't bother
        guard !targetAppBundle.appExtensions.isEmpty else {
            return self.finish(.success(()))
        }
        
        // process extensionsInfo
        let excessExtensions = processExtensionsInfo(from: targetAppBundle, appInDatabase: appInDatabase)

        DispatchQueue.main.async {
            guard let presentingViewController: UIViewController = presentingViewController,
                  presentingViewController.viewIfLoaded?.window != nil else {
                // background mode: remove only the excess extensions automatically for re-installs
                //                  keep all extensions for fresh install (appInDatabase = nil)
                return self.backgroundModeExtensionsCleanup(excessExtensions: excessExtensions)
            }

            // present prompt to the user if we have a view context
            let alertController = self.createAlertDialog(from: targetAppBundle, extensions: extensions, presentingViewController)
            presentingViewController.present(alertController, animated: true){

                // if for any reason the view wasn't presented, then just signal that as error
                if presentingViewController.presentedViewController == nil {
                    let errMsg = "RemoveAppExtensionsOperation: unable to present dialog, view context not available." +
                                 "\nDid you move to different screen or background after starting the operation?"
                    self.finish(.failure(
                        OperationError.invalidOperationContext(errMsg)
                    ))
                }
            }
        }
    }
    
    private func createAlertDialog(from targetAppBundle: ALTApplication,
                              extensions: Set<ALTApplication>,
                              _ presentingViewController: UIViewController) -> UIAlertController
    {
        
        /// Foreground prompt:
        let firstSentence: String
        
        if UserDefaults.standard.activeAppLimitIncludesExtensions
        {
            firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions.", comment: "")
        }
        else
        {
            firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to creating 10 App IDs per week.", comment: "")
        }
        
        let message = firstSentence + " " + NSLocalizedString("Would you like to remove this app's extensions so they don't count towards your limit? There are \(extensions.count) Extensions", comment: "")
        
        
        
        let alertController = UIAlertController(title: NSLocalizedString("App Contains Extensions", comment: ""), message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: { (action) in
            self.finish(.failure(OperationError.cancelled))
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions", comment: ""), style: .default) { (action) in
            self.finish(.success(()))
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove App Extensions", comment: ""), style: .destructive) { (action) in
            do {
                try Self.removeExtensions(from: targetAppBundle.appExtensions)
                return self.finish(.success(()))
            } catch {
                return self.finish(.failure(error))
            }
        })
        
        
        
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Choose App Extensions", comment: ""), style: .default) { (action) in

            
            let popoverContentController = AppExtensionViewHostingController(extensions: extensions) { (selection) in
                do {
                    try Self.removeExtensions(from: Set(selection))
                    return self.finish(.success(()))
                } catch {
                    return self.finish(.failure(error))
                }
            }
            
            let suiview = popoverContentController.view!
            suiview.translatesAutoresizingMaskIntoConstraints = false
            
            popoverContentController.modalPresentationStyle = .popover
            
            if let popoverPresentationController = popoverContentController.popoverPresentationController {
                popoverPresentationController.sourceView = presentingViewController.view
                popoverPresentationController.sourceRect = CGRect(x: 50, y: 50, width: 4, height: 4)
                popoverPresentationController.delegate = popoverContentController
                
                DispatchQueue.main.async {
                    presentingViewController.present(popoverContentController, animated: true)
                }
            }else{
                self.finish(.failure(
                    OperationError.invalidParameters("RemoveAppExtensionsOperation: popoverContentController.popoverPresentationController is nil"))
                )
            }
        })
        
        return alertController
    }
    
    struct ExtensionsInfo{
        let excessInTarget: Set<ALTApplication>
        let necessaryInExisting: Set<ALTApplication>
    }
    
    private func processExtensionsInfo(from targetAppBundle: ALTApplication,
                                       appInDatabase: ALTApplication?) -> Set<ALTApplication>
    {
        //App-Extensions: Ensure existing app's extensions in DB and currently installing app bundle's extensions must match
        let targetAppEx: Set<ALTApplication> = targetAppBundle.appExtensions
        let targetAppExNames  = targetAppEx.map{ appEx in appEx.bundleIdentifier}

        guard let extensionsInExistingApp = appInDatabase?.appExtensions else {
            let diagnosticsMsg = "RemoveAppExtensionsOperation: ExistingApp is nil, Hence keeping all app extensions from targetAppBundle"
                               + "RemoveAppExtensionsOperation: ExistingAppEx: nil; targetAppBundleEx: \(targetAppExNames)"
            print(diagnosticsMsg)
            return Set()    // nothing is excess since we are keeping all, so returning empty
        }
        
        let existingAppEx: Set<ALTApplication> = extensionsInExistingApp
        
        let existingAppExNames = existingAppEx.map{ appEx in appEx.bundleIdentifier}
        
        let excessExtensionsInTargetApp = targetAppEx.filter{
            !(existingAppExNames.contains($0.bundleIdentifier))
        }
        
        let excessExtensionsInExistingApp = existingAppEx.filter{
            !(targetAppExNames.contains($0.bundleIdentifier))
        }
    
        let isMatching = (targetAppEx.count == existingAppEx.count) && excessExtensionsInTargetApp.isEmpty
        let diagnosticsMsg = "RemoveAppExtensionsOperation: App Extensions in existingApp and targetAppBundle are matching: \(isMatching)\n"
                           + "RemoveAppExtensionsOperation: existingAppEx: \(existingAppExNames); targetAppBundleEx: \(String(describing: targetAppExNames))\n"
        print(diagnosticsMsg)

        return excessExtensionsInTargetApp
    }
    
    private func backgroundModeExtensionsCleanup(excessExtensions: Set<ALTApplication>) {
        // perform silent extensions cleanup for those that aren't already present in existing app
        print("\n    Performing background mode Extensions removal    \n")
        print("RemoveAppExtensionsOperation: Excess Extensions In TargetAppBundle: \(excessExtensions.map{$0.bundleIdentifier})")
        
        do {
            try Self.removeExtensions(from: excessExtensions)
            return self.finish(.success(()))
        } catch {
            return self.finish(.failure(error))
        }
    }
}
