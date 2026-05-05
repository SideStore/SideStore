//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

import WidgetKit

import AltSign
import AltStoreCore
import UniformTypeIdentifiers

let pairingFileName = "ALTPairingFile.mobiledevicepairing"

final class LaunchViewController: UIViewController, UIDocumentPickerDelegate {
    private var didFinishLaunching = false
    private var retries = 0
    private var maxRetries = 3
    private var splashView: SplashView!
    private var destinationViewController: TabBarController?
    private var startTime: Date!

    override func viewDidLoad() {
        super.viewDidLoad()
        splashView = SplashView(frame: view.bounds, appName: "SideStore")
        destinationViewController = storyboard!.instantiateViewController(withIdentifier: "tabBarController") as? TabBarController
        view.addSubview(splashView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didFinishLaunching else { return }
        Task {
            startTime = Date()
            await runLaunchSequence()
            doPostLaunch()
        }
    }

    private func runLaunchSequence() async {
        guard retries < maxRetries else { return }
        retries += 1

        await Task.detached {
            if !DatabaseManager.shared.isStarted {
                await withCheckedContinuation { continuation in
                    DatabaseManager.shared.start { error in
                        if let error {
                            Task { await self.handleLaunchError(error, retryCallback: self.runLaunchSequence) }
                        } else {
                            Task { await self.finishLaunching() }
                        }
                        continuation.resume(returning: ())
                    }
                }
            } else {
                await self.finishLaunching()
            }
        }.value
    }

    private func doPostLaunch() {
        SideJITManager.shared.checkAndPromptIfNeeded(presentingVC: self)
        if #available(iOS 17, *), UserDefaults.standard.sidejitenable {
            DispatchQueue.global().async { SideJITManager.shared.askForNetwork() }
            print("SideJITServer Enabled")
        }

        #if !targetEnvironment(simulator)
        
        detectAndImportAccountFile()
        
        if UserDefaults.standard.enableEMPforWireguard {
            startEMProxy(bind_addr: AppConstants.Proxy.serverURL)
        }
        guard let pf = fetchPairingFile() else {
            displayError("Device pairing file not found.")
            return
        }
        start_minimuxer_threads(pf)
        #endif
    }

    func start_minimuxer_threads(_ pairing_file: String) {
        retargetUsbmuxdAddr()
        let documentsDirectory = FileManager.default.documentsDirectory.absoluteString
        do {
            let loggingEnabled = UserDefaults.standard.isMinimuxerConsoleLoggingEnabled
            try minimuxerStartWithLogger(pairing_file, documentsDirectory, loggingEnabled)
        } catch {
            try! FileManager.default.removeItem(at: FileManager.default.documentsDirectory.appendingPathComponent(pairingFileName))
            displayError("minimuxer failed to start, please restart SideStore. \((error as? LocalizedError)?.failureReason ?? "UNKNOWN ERROR")")
        }
        startAutoMounter(documentsDirectory)
    }

    func fetchPairingFile() -> String? { PairingFileManager.shared.fetchPairingFile(presentingVC: self) }

    func displayError(_ msg: String) {
        print(msg)
        let alert = UIAlertController(title: "Error launching SideStore", message: msg, preferredStyle: .alert)
        self.present(alert, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        let isSecuredURL = url.startAccessingSecurityScopedResource() == true
        defer {
            if (isSecuredURL) {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let pairingString = String(data: data, encoding: .utf8) else {
                displayError("Unable to read pairing file")
                return
            }
            try pairingString.write(to: FileManager.default.documentsDirectory.appendingPathComponent(pairingFileName), atomically: true, encoding: .utf8)
            start_minimuxer_threads(pairingString)
        } catch {
            displayError("Unable to read pairing file")
        }
        
        controller.dismiss(animated: true, completion: nil)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        displayError("Choosing a pairing file was cancelled. Please re-open the app and try again.")
    }
    
    func importAccountAtFile(_ file: URL, remove: Bool = false) {
        _ = file.startAccessingSecurityScopedResource()
        defer { file.stopAccessingSecurityScopedResource() }
        guard let accountD = try? Data(contentsOf: file) else {
            return Logger.main.notice("Could not parse data from file \(file)")
        }
        guard let account = try? Foundation.JSONDecoder().decode(ImportedAccount.self, from: accountD) else {
            return Logger.main.notice("Could not parse data from file \(file)")
        }
        print("We want to import this account probably: \(account)")
        if remove {
            try? FileManager.default.removeItem(at: file)
        }
        Keychain.shared.appleIDEmailAddress = account.email
        Keychain.shared.appleIDPassword = account.password
        Keychain.shared.adiPb = account.adiPB
        Keychain.shared.identifier = account.local_user
        if let altCert = ALTCertificate(p12Data: account.cert, password: account.certpass) {
            Keychain.shared.signingCertificate = altCert.encryptedP12Data(withPassword: "")!
            Keychain.shared.signingCertificatePassword = account.certpass
            let toastView = ToastView(text: NSLocalizedString("Successfully imported '\(account.email)'!", comment: ""), detailText: "SideStore should be fully operational!")
            return toastView.show(in: self)
        } else {
            let toastView = ToastView(text: NSLocalizedString("Failed to import account certificate!", comment: ""), detailText: "Failed to create ALTCertificate. Check if the password is correct. Still imported account/adi.pb details!")
            return toastView.show(in: self)
        }
    }
    
    func detectAndImportAccountFile() {
        let accountFileURL = FileManager.default.documentsDirectory.appendingPathComponent("Account.sideconf")
        #if !DEBUG
        importAccountAtFile(accountFileURL, remove: true)
        #else
        importAccountAtFile(accountFileURL)
        #endif
    }
}

extension LaunchViewController {
    @MainActor
    func handleLaunchError(_ error: Error, retryCallback: (() async -> Void)? = nil) {
        do { throw error } catch let error as NSError {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
            let desc: String
            if #available(iOS 14.5, *) {
                desc = ([error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }).joined(separator: "\n\n")
            } else {
                desc = error.debugDescription
            }
            let alert = UIAlertController(title: title, message: desc, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
                Task { await retryCallback?() }
            })
            present(alert, animated: true)
        }
    }

    @MainActor
    func finishLaunching() async {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true
        
        AppManager.shared.update()
        AppManager.shared.updateAllSources { result in
            guard case .failure(let error) = result else { return }
            Logger.main.error("Failed to update sources on launch. \(error.localizedDescription, privacy: .public)")
            
            
            let errorDesc = ErrorProcessing(.fullError).getDescription(error: error as NSError)
            print("Failed to update sources on launch. \(errorDesc)")
            
            var mode: ToastView.InfoMode = .fullError
            if String(describing: error).contains("The Internet connection appears to be offline"){
                mode = .localizedDescription    // dont make noise!
            }
            let toastView = ToastView(error: error, mode: mode)
            toastView.addTarget(self.destinationViewController, action: #selector(TabBarController.presentSources), for: .touchUpInside)
            toastView.show(in: self.destinationViewController!.selectedViewController ?? self.destinationViewController!)
        }
        updateKnownSources()
        WidgetCenter.shared.reloadAllTimelines()
        didFinishLaunching = true
        
        let destinationVC = destinationViewController!
        
        let elapsed = abs(startTime.timeIntervalSinceNow)
        let remaining = elapsed >= 1 ? 0 : 1 - elapsed
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        
        destinationVC.loadViewIfNeeded()
        addChild(destinationVC)
        destinationVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(destinationVC.view)
        destinationVC.didMove(toParent: self)
        
        // Pin edges BEFORE animation
        NSLayoutConstraint.activate([
            destinationVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            destinationVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            destinationVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            destinationVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Set initial alpha for fade-in
        destinationVC.view.alpha = 0

        UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) { [self] in
            self.splashView.alpha = 0
            destinationVC.view.alpha = 1
        } completion: { _ in
            self.splashView.removeFromSuperview()
            self.destinationViewController = destinationVC
        }
    }

    func updateKnownSources() {
        AppManager.shared.updateKnownSources { result in
            switch result {
            case .failure(let error): print("[ALTLog] Failed to update known sources:", error)
            case .success((_, let blockedSources)):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                    let blockedSourceIDs = Set(blockedSources.lazy.map { $0.identifier })
                    let blockedSourceURLs = Set(blockedSources.lazy.compactMap { $0.sourceURL })
                    let predicate = NSPredicate(format: "%K IN %@ OR %K IN %@", #keyPath(Source.identifier), blockedSourceIDs, #keyPath(Source.sourceURL), blockedSourceURLs)
                    let sourceErrors = Source.all(satisfying: predicate, in: context).map { source in
                        let blocked = blockedSources.first { $0.identifier == source.identifier }
                        return SourceError.blocked(source, bundleIDs: blocked?.bundleIDs, existingSource: source)
                    }
                    guard !sourceErrors.isEmpty else { return }
                    Task {
                        for error in sourceErrors {
                            let title = String(format: NSLocalizedString("“%@” Blocked", comment: ""), error.$source.name)
                            let message = [error.localizedDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                            await self.presentAlert(title: title, message: message)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SplashView
final class SplashView: UIView {
    let iconView = UIImageView()
    let titleLabel = UILabel()

    init(frame: CGRect, appName: String) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        setupIcon()
        setupTitle(appName: appName)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupIcon() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.25
        container.layer.shadowOffset = CGSize(width: 0, height: 4)
        container.layer.shadowRadius = 8
        addSubview(container)

        iconView.image = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") ?? UIImage(systemName: "app.fill")
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 24
        iconView.clipsToBounds = true
        container.addSubview(iconView)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            container.widthAnchor.constraint(equalToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 120),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    private func setupTitle(appName: String) {
        titleLabel.text = appName
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
}

// MARK: - PairingFileManager
final class PairingFileManager {
    static let shared = PairingFileManager()
    func fetchPairingFile(presentingVC: UIViewController) -> String? {
        let fm = FileManager.default
        let filename = pairingFileName
        let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
        if fm.fileExists(atPath: documentsPath.path),
           let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
            return contents
        }
        if let url = Bundle.main.url(forResource: "ALTPairingFile", withExtension: "mobiledevicepairing"),
           fm.fileExists(atPath: url.path),
           let data = fm.contents(atPath: url.path),
           let contents = String(data: data, encoding: .utf8),
           !contents.isEmpty, !UserDefaults.standard.isPairingReset { return contents }
        if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
           !plistString.isEmpty, !plistString.contains("insert pairing file here"), !UserDefaults.standard.isPairingReset { return plistString }

        presentPairingFileAlert(on: presentingVC)
        return nil
    }

    private func presentPairingFileAlert(on vc: UIViewController) {
        let alert = UIAlertController(title: "Pairing File", message: "Select the pairing file or select \"Help\" for help.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Help", style: .default) { _ in
            if let url = URL(string: "https://docs.sidestore.io/docs/advanced/pairing-file") { UIApplication.shared.open(url) }
            sleep(2); exit(0)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            var types = UTType.types(tag: "plist", tagClass: .filenameExtension, conformingTo: nil)
            types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: .filenameExtension, conformingTo: .data))
            types.append(.xml)
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
            picker.delegate = vc as? UIDocumentPickerDelegate
            picker.shouldShowFileExtensions = true
            vc.present(picker, animated: true)
            UserDefaults.standard.isPairingReset = false
        })
        vc.present(alert, animated: true)
    }
}

// MARK: - SideJITManager
final class SideJITManager {
    static let shared = SideJITManager()
    func checkAndPromptIfNeeded(presentingVC: UIViewController) {
        guard #available(iOS 17, *), !UserDefaults.standard.sidejitenable else { return }
        DispatchQueue.global().async {
            self.isSideJITServerDetected { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success():
                        let alert = UIAlertController(title: "SideJITServer Detected", message: "Would you like to enable SideJITServer", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in UserDefaults.standard.sidejitenable = true })
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        presentingVC.present(alert, animated: true)
                    case .failure(_): print("Cannot find sideJITServer")
                    }
                }
            }
        }
    }

    func askForNetwork() {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        let SJSURL = address.isEmpty ? "http://sidejitserver._http._tcp.local:8080" : address
        URLSession.shared.dataTask(with: URL(string: "\(SJSURL)/re/")!) { data, resp, err in
            print("data: \(String(describing: data)), response: \(String(describing: resp)), error: \(String(describing: err))")
        }.resume()
    }

    func isSideJITServerDetected(completion: @escaping (Result<Void, Error>) -> Void) {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        let SJSURL = address.isEmpty ? "http://sidejitserver._http._tcp.local:8080" : address
        guard let url = URL(string: SJSURL) else { return }
        URLSession.shared.dataTask(with: url) { _, _, error in
            if let error = error { completion(.failure(error)); return }
            completion(.success(()))
        }.resume()
    }
}
