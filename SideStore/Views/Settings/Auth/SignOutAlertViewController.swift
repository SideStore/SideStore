//
//  SignOutAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 6/29/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
@preconcurrency import UIKit
import Foundation

class SignOutAlertViewController: UIViewController {
    let certCheckboxButton = UIButton(type: .system)
    let anisetteCheckboxButton = UIButton(type: .system)
    let anisetteHeadersCheckboxButton = UIButton(type: .system)
    let sideSignHeadersCheckboxButton = UIButton(type: .system)
    
    var isChecked: Bool = true {
        didSet {
            updateButtonImage(certCheckboxButton, isChecked: isChecked)
        }
    }
    
    var isKeepAnisetteChecked: Bool = true {
        didSet {
            updateButtonImage(anisetteCheckboxButton, isChecked: isKeepAnisetteChecked)
        }
    }
    
    var isKeepAnisetteHeadersChecked: Bool = true {
        didSet {
            updateButtonImage(anisetteHeadersCheckboxButton, isChecked: isKeepAnisetteHeadersChecked)
        }
    }

    var isKeepSideSignHeadersChecked: Bool = true {
        didSet {
            updateButtonImage(sideSignHeadersCheckboxButton, isChecked: isKeepSideSignHeadersChecked)
        }
    }
    
    private func updateButtonImage(_ button: UIButton, isChecked: Bool) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        button.setImage(image, for: .normal)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        isChecked = UserDefaults.standard.keepSigningCertsAfterLogout
        isKeepAnisetteChecked = UserDefaults.standard.keepAnisetteDataAfterLogout
        isKeepAnisetteHeadersChecked = UserDefaults.standard.keepAnisetteHeadersAfterLogout
        isKeepSideSignHeadersChecked = UserDefaults.standard.keepSideSignHeadersAfterLogout
        
        certCheckboxButton.tintColor = .systemBlue
        certCheckboxButton.imageView?.contentMode = .scaleAspectFit
        certCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        certCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            certCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            certCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        certCheckboxButton.addTarget(self, action: #selector(toggleCertCheckbox), for: .touchUpInside)
        
        let certLabel = UILabel()
        certLabel.text = NSLocalizedString("Keep signing certificate", comment: "")
        certLabel.font = .systemFont(ofSize: 14)
        certLabel.isUserInteractionEnabled = true
        let certTap = UITapGestureRecognizer(target: self, action: #selector(toggleCertCheckbox))
        certLabel.addGestureRecognizer(certTap)
        
        let certStack = UIStackView(arrangedSubviews: [certCheckboxButton, certLabel])
        certStack.axis = .horizontal
        certStack.spacing = 8
        certStack.alignment = .center
        
        anisetteCheckboxButton.tintColor = .systemBlue
        anisetteCheckboxButton.imageView?.contentMode = .scaleAspectFit
        anisetteCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        anisetteCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            anisetteCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            anisetteCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        anisetteCheckboxButton.addTarget(self, action: #selector(toggleAnisetteCheckbox), for: .touchUpInside)
        
        let anisetteLabel = UILabel()
        anisetteLabel.text = NSLocalizedString("Keep Anisette data", comment: "")
        anisetteLabel.font = .systemFont(ofSize: 14)
        anisetteLabel.isUserInteractionEnabled = true
        let anisetteTap = UITapGestureRecognizer(target: self, action: #selector(toggleAnisetteCheckbox))
        anisetteLabel.addGestureRecognizer(anisetteTap)
        
        let anisetteStack = UIStackView(arrangedSubviews: [anisetteCheckboxButton, anisetteLabel])
        anisetteStack.axis = .horizontal
        anisetteStack.spacing = 8
        anisetteStack.alignment = .center

        anisetteHeadersCheckboxButton.tintColor = .systemBlue
        anisetteHeadersCheckboxButton.imageView?.contentMode = .scaleAspectFit
        anisetteHeadersCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        anisetteHeadersCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            anisetteHeadersCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            anisetteHeadersCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        anisetteHeadersCheckboxButton.addTarget(self, action: #selector(toggleAnisetteHeadersCheckbox), for: .touchUpInside)
        
        let anisetteHeadersLabel = UILabel()
        anisetteHeadersLabel.text = NSLocalizedString("Keep Anisette headers", comment: "")
        anisetteHeadersLabel.font = .systemFont(ofSize: 14)
        anisetteHeadersLabel.isUserInteractionEnabled = true
        let anisetteHeadersTap = UITapGestureRecognizer(target: self, action: #selector(toggleAnisetteHeadersCheckbox))
        anisetteHeadersLabel.addGestureRecognizer(anisetteHeadersTap)
        
        let anisetteHeadersStack = UIStackView(arrangedSubviews: [anisetteHeadersCheckboxButton, anisetteHeadersLabel])
        anisetteHeadersStack.axis = .horizontal
        anisetteHeadersStack.spacing = 8
        anisetteHeadersStack.alignment = .center

        sideSignHeadersCheckboxButton.tintColor = .systemBlue
        sideSignHeadersCheckboxButton.imageView?.contentMode = .scaleAspectFit
        sideSignHeadersCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        sideSignHeadersCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            sideSignHeadersCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            sideSignHeadersCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        sideSignHeadersCheckboxButton.addTarget(self, action: #selector(toggleSideSignHeadersCheckbox), for: .touchUpInside)
        
        let sideSignHeadersLabel = UILabel()
        sideSignHeadersLabel.text = NSLocalizedString("Keep SideSign headers", comment: "")
        sideSignHeadersLabel.font = .systemFont(ofSize: 14)
        sideSignHeadersLabel.isUserInteractionEnabled = true
        let sideSignHeadersTap = UITapGestureRecognizer(target: self, action: #selector(toggleSideSignHeadersCheckbox))
        sideSignHeadersLabel.addGestureRecognizer(sideSignHeadersTap)
        
        let sideSignHeadersStack = UIStackView(arrangedSubviews: [sideSignHeadersCheckboxButton, sideSignHeadersLabel])
        sideSignHeadersStack.axis = .horizontal
        sideSignHeadersStack.spacing = 8
        sideSignHeadersStack.alignment = .center
        
        let mainStackView = UIStackView(arrangedSubviews: [certStack, anisetteStack, anisetteHeadersStack, sideSignHeadersStack])
        mainStackView.axis = .vertical
        mainStackView.spacing = 8
        mainStackView.alignment = .leading
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            mainStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            mainStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        self.preferredContentSize = CGSize(width: 270, height: 128)
    }
    
    @objc func toggleCertCheckbox() {
        isChecked.toggle()
        UserDefaults.standard.keepSigningCertsAfterLogout = isChecked
    }
    
    @objc func toggleAnisetteCheckbox() {
        isKeepAnisetteChecked.toggle()
        UserDefaults.standard.keepAnisetteDataAfterLogout = isKeepAnisetteChecked
    }

    @objc func toggleAnisetteHeadersCheckbox() {
        isKeepAnisetteHeadersChecked.toggle()
        UserDefaults.standard.keepAnisetteHeadersAfterLogout = isKeepAnisetteHeadersChecked
    }

    @objc func toggleSideSignHeadersCheckbox() {
        isKeepSideSignHeadersChecked.toggle()
        UserDefaults.standard.keepSideSignHeadersAfterLogout = isKeepSideSignHeadersChecked
    }
}
