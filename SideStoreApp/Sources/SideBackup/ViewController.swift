//
//  ViewController.swift
//  AltBackup
//
//  Created by Riley Testut on 5/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

extension Bundle {
    var appName: String? {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        return appName
    }
}

extension ViewController {
    enum BackupOperation {
        case backup
        case restore
    }
}

class ViewController: UIViewController {
    private let backupController = BackupController()

    private var currentOperation: BackupOperation? {
        didSet {
            DispatchQueue.main.async {
                self.update()
            }
        }
    }

    private var textLabel: UILabel!
    private var detailTextLabel: UILabel!
    private var activityIndicatorView: UIActivityIndicatorView!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.backup), name: AppDelegate.startBackupNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.restore), name: AppDelegate.startRestoreNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .altstoreBackground

        textLabel = UILabel(frame: .zero)
        textLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        textLabel.textColor = .altstoreText
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0

        detailTextLabel = UILabel(frame: .zero)
        detailTextLabel.font = UIFont.preferredFont(forTextStyle: .body)
        detailTextLabel.textColor = .altstoreText
        detailTextLabel.textAlignment = .center
        detailTextLabel.numberOfLines = 0

        activityIndicatorView = UIActivityIndicatorView(style: .whiteLarge)
        activityIndicatorView.color = .altstoreText
        activityIndicatorView.startAnimating()

        #if DEBUG
            let button1 = UIButton(type: .system)
            button1.setTitle("Backup", for: .normal)
            button1.setTitleColor(.white, for: .normal)
            button1.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
            button1.addTarget(self, action: #selector(ViewController.backup), for: .primaryActionTriggered)

            let button2 = UIButton(type: .system)
            button2.setTitle("Restore", for: .normal)
            button2.setTitleColor(.white, for: .normal)
            button2.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
            button2.addTarget(self, action: #selector(ViewController.restore), for: .primaryActionTriggered)

            let arrangedSubviews = [textLabel!, detailTextLabel!, activityIndicatorView!, button1, button2]
        #else
            let arrangedSubviews = [textLabel!, detailTextLabel!, activityIndicatorView!]
        #endif

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 22
        stackView.axis = .vertical
        stackView.alignment = .center
        view.addSubview(stackView)

        NSLayoutConstraint.activate([stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                                     stackView.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.safeAreaLayoutGuide.leadingAnchor, multiplier: 1.0),
                                     view.safeAreaLayoutGuide.trailingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: stackView.trailingAnchor, multiplier: 1.0)])

        update()
    }
}

private extension ViewController {
    @objc func backup() {
        currentOperation = .backup

        backupController.performBackup { result in
            let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")

            let title = String(format: NSLocalizedString("%@ could not be backed up.", comment: ""), appName)
            self.process(result, errorTitle: title)
        }
    }

    @objc func restore() {
        currentOperation = .restore

        backupController.restoreBackup { result in
            let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")

            let title = String(format: NSLocalizedString("%@ could not be restored.", comment: ""), appName)
            self.process(result, errorTitle: title)
        }
    }

    func update() {
        switch currentOperation {
        case .backup:
            textLabel.text = NSLocalizedString("Backing up app data…", comment: "")
            detailTextLabel.isHidden = true
            activityIndicatorView.startAnimating()

        case .restore:
            textLabel.text = NSLocalizedString("Restoring app data…", comment: "")
            detailTextLabel.isHidden = true
            activityIndicatorView.startAnimating()

        case .none:
            textLabel.text = String(format: NSLocalizedString("%@ is inactive.", comment: ""),
                                    Bundle.main.appName ?? NSLocalizedString("App", comment: ""))

            detailTextLabel.text = String(format: NSLocalizedString("Refresh %@ in SideStore to continue using it.", comment: ""),
                                          Bundle.main.appName ?? NSLocalizedString("this app", comment: ""))

            detailTextLabel.isHidden = false
            activityIndicatorView.stopAnimating()
        }
    }
}

private extension ViewController {
    func process(_ result: Result<Void, Error>, errorTitle: String) {
        DispatchQueue.main.async {
            switch result {
            case .success: break
            case let .failure(error as NSError):
                let message: String

                if let sourceDescription = error.sourceDescription {
                    message = error.localizedDescription + "\n\n" + sourceDescription
                } else {
                    message = error.localizedDescription
                }

                let alertController = UIAlertController(title: errorTitle, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }

            NotificationCenter.default.post(name: AppDelegate.operationDidFinishNotification, object: nil, userInfo: [AppDelegate.operationResultKey: result])
        }
    }

    @objc func didEnterBackground(_: Notification) {
        // Reset UI once we've left app (but not before).
        currentOperation = nil
    }
}
