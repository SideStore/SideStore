//
//  ResetAdiAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 11/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class ResetAdiAlertViewController: UIViewController {
    let headersCheckboxButton = UIButton(type: .system)
    
    var isKeepHeadersChecked: Bool = true {
        didSet {
            updateButtonImage(headersCheckboxButton, isChecked: isKeepHeadersChecked)
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
        
        isKeepHeadersChecked = UserDefaults.standard.keepAnisetteHeadersAfterLogout
        
        headersCheckboxButton.tintColor = .systemBlue
        headersCheckboxButton.imageView?.contentMode = .scaleAspectFit
        headersCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        headersCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            headersCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            headersCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        headersCheckboxButton.addTarget(self, action: #selector(toggleHeadersCheckbox), for: .touchUpInside)
        
        let headersLabel = UILabel()
        headersLabel.text = NSLocalizedString("Keep header customizations", comment: "")
        headersLabel.font = .systemFont(ofSize: 14)
        headersLabel.isUserInteractionEnabled = true
        let headersTap = UITapGestureRecognizer(target: self, action: #selector(toggleHeadersCheckbox))
        headersLabel.addGestureRecognizer(headersTap)
        
        let headersStack = UIStackView(arrangedSubviews: [headersCheckboxButton, headersLabel])
        headersStack.axis = .horizontal
        headersStack.spacing = 8
        headersStack.alignment = .center
        headersStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(headersStack)
        
        NSLayoutConstraint.activate([
            headersStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            headersStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            headersStack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        self.preferredContentSize = CGSize(width: 270, height: 32)
    }
    
    @objc func toggleHeadersCheckbox() {
        isKeepHeadersChecked.toggle()
        UserDefaults.standard.keepAnisetteHeadersAfterLogout = isKeepHeadersChecked
    }
}
