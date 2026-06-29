//
//  SignOutAlertViewController.swift
//  AltStore
//
//  Created by Magesh K on 6/29/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import UIKit
import Foundation

class SignOutAlertViewController: UIViewController {
    let checkboxButton = UIButton(type: .system)
    var isChecked: Bool = true {
        didSet {
            let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            let imageName = isChecked ? "checkmark.square.fill" : "square"
            let image = UIImage(systemName: imageName, withConfiguration: configuration)
            checkboxButton.setImage(image, for: .normal)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        isChecked = UserDefaults.standard.keepSigningCertsAfterLogout
        
        checkboxButton.tintColor = .systemBlue
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        
        let label = UILabel()
        label.text = NSLocalizedString("Keep signing certificate", comment: "")
        label.font = .systemFont(ofSize: 15)
        label.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleCheckbox))
        label.addGestureRecognizer(tapGesture)
        
        let stackView = UIStackView(arrangedSubviews: [checkboxButton, label])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        self.preferredContentSize = CGSize(width: 270, height: 40)
    }
    
    @objc func toggleCheckbox() {
        isChecked.toggle()
        UserDefaults.standard.keepSigningCertsAfterLogout = isChecked
    }
}

