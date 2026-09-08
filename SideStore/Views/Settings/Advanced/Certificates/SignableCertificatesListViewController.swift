//
//  SignableCertificatesListViewController.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SwiftUI
import SideSign

struct SignableCertificateRowView: View {
    let cert: ALTCertificate
    let appName: String
    let appCertSerial: String?
    @ObservedObject var viewModel: CertificatesViewModel
    
    private var isAppCert: Bool {
        guard let appCertSerial else { return false }
        return cert.serialNumber == appCertSerial
    }
    private var isActiveGlobal: Bool {
        cert.serialNumber == viewModel.activeSerialNumber
    }
    
    private var briefInfo: CertificateBriefInfo? { getBriefInfo(for: cert.data) }
    
    private var statusText: String? {
        if isAppCert && isActiveGlobal {
            return "Current App & Active Global"
        } else if isAppCert {
            return "Current App"
        } else if isActiveGlobal {
            return "Active Global"
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cert.machineName ?? cert.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                let certName = cert.name
                if cert.machineName != nil {
                    (
                        Text("Name: ").font(.system(size: 10))
                        + Text(certName).font(.system(size: 10))
                    )
                    .foregroundColor(Color(uiColor: .lightGray))
                }
                
                (
                    Text("Serial: ").font(.system(size: 11))
                    + Text(cert.serialNumber).font(.system(size: 11, design: .monospaced))
                )
                .foregroundColor(Color(uiColor: .lightGray))
                
                if let ident = cert.identifier, !ident.isEmpty {
                    (
                        Text("ID: ").font(.system(size: 10))
                        + Text(ident).font(.system(size: 10, design: .monospaced))
                    )
                    .foregroundColor(Color(uiColor: .lightGray))
                }
                
                if let brief = briefInfo {
                    (
                        Text("Type: ").font(.system(size: 10))
                        + Text(brief.type).font(.system(size: 10))
                    )
                    .foregroundColor(Color(uiColor: .lightGray))
                    
                    (
                        Text("Validity: ").font(.system(size: 10))
                        + Text(String(format: NSLocalizedString("%@ - %@", comment: ""), brief.validFrom, brief.validUntil)).font(.system(size: 10))
                    )
                    .foregroundColor(Color(uiColor: .lightGray))
                }
                
                if let req = cert.requesterEmail, !req.isEmpty {
                    (
                        Text("Requester: ").font(.system(size: 10))
                        + Text(req).font(.system(size: 10))
                    )
                    .foregroundColor(Color(uiColor: .lightGray))
                }
                
                (
                    Text("Keys: ").font(.system(size: 10))
                    + Text("public + private").font(.system(size: 10))
                )
                .foregroundColor(Color(uiColor: .lightGray))
                
                if let status = statusText {
                    (
                        Text("Status: ").font(.system(size: 10))
                        + Text(status).font(.system(size: 10, weight: .bold))
                    )
                    .foregroundColor(isAppCert ? .green : .cyan)
                }
            }
            
            Spacer()
            
            if isAppCert {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

final class SignableCertificatesListViewController: UITableViewController {
    let installedApp: InstalledApp
    let viewModel: CertificatesViewModel
    var onSelectCertificate: ((ALTCertificate) -> Void)?
    
    private var certificates: [ALTCertificate] = []
    
    init(installedApp: InstalledApp, viewModel: CertificatesViewModel = CertificatesViewModel()) {
        self.installedApp = installedApp
        self.viewModel = viewModel
        #if !os(tvOS)
        super.init(style: .insetGrouped)
        #else
        super.init(style: .grouped)
        #endif
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Set Certificate", comment: "")
        self.certificates = viewModel.loadAllSignableLocalCertificates()
        
        self.view.backgroundColor = .settingsBackground
        self.tableView.backgroundColor = .settingsBackground
        
        #if !os(tvOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .settingsBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        #endif
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        self.navigationItem.leftBarButtonItem?.tintColor = .white
        
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CertCell")
    }
    
    @objc private func cancelTapped() {
        self.dismiss(animated: true)
    }
    
    func present(from presentingViewController: UIViewController) {
        let signableCerts = viewModel.loadAllSignableLocalCertificates()
        
        guard !signableCerts.isEmpty else {
            let alert = UIAlertController(
                title: NSLocalizedString("No Signing Certificates", comment: ""),
                message: NSLocalizedString("No valid signing certificates with private keys were found locally. Please import or create a certificate in Settings -> Certificates first.", comment: ""),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            presentingViewController.present(alert, animated: true)
            return
        }
        
        let nav = UINavigationController(rootViewController: self)
        #if !os(tvOS)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        #else
        nav.modalPresentationStyle = .fullScreen
        #endif
        presentingViewController.present(nav, animated: true)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return certificates.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CertCell", for: indexPath)
        let cert = certificates[indexPath.row]
        let isCurrent = (cert.serialNumber == installedApp.certificateSerialNumber)
        
        debugLog("[SignableCertList] cellForRowAt[\(indexPath.row)]: serial='\(cert.serialNumber)', name='\(cert.name)', machineName='\(cert.machineName ?? "nil")', email='\(cert.requesterEmail ?? "nil")'")
        
        if #available(iOS 16.0, tvOS 16.0, *) {
            cell.contentConfiguration = UIHostingConfiguration {
                SignableCertificateRowView(cert: cert, appName: installedApp.name, appCertSerial: installedApp.certificateSerialNumber, viewModel: viewModel)
            }
            .background(Color.white.opacity(0.15))
        } else {
            let certName = cert.name
            let machineName = cert.machineName ?? "N/A"
            let brief = getBriefInfo(for: cert.data)
            let typeStr = brief?.type ?? "N/A"
            let validityStr = brief != nil ? "\(brief!.validFrom) - \(brief!.validUntil)" : "N/A"
            
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.text = """
            \(certName) [Machine: \(machineName)]\(isCurrent ? " (Current)" : "")
            Serial: \(cert.serialNumber)
            ID: \(cert.identifier ?? "N/A")
            Type: \(typeStr)
            Validity: \(validityStr)
            Requester: \(cert.requesterEmail ?? "N/A")
            Keys: public + private
            """
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .systemFont(ofSize: 12, weight: .regular)
            cell.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            cell.accessoryType = isCurrent ? .checkmark : .none
            cell.tintColor = .green
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cert = certificates[indexPath.row]
        
        let contentVC = SetCertificateAlertViewController(installedApp: self.installedApp, certificate: cert.x509)
        let confirmAlert = UIAlertController(
            title: NSLocalizedString("Set Certificate Confirmation", comment: ""),
            message: NSLocalizedString("Confirm applying this certificate:", comment: ""),
            preferredStyle: .alert
        )
        confirmAlert.setValue(contentVC, forKey: "contentViewController")
        
        let setAction = UIAlertAction(title: NSLocalizedString("Set & Resign", comment: ""), style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSelectCertificate?(cert)
            }
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        
        confirmAlert.addAction(cancelAction)
        confirmAlert.addAction(setAction)
        
        self.present(confirmAlert, animated: true)
    }
}
