//
//  PairingFileEditAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class PairingFileEditAlertViewController: UIViewController {
    let checkboxButton = UIButton(type: .system)
    
    var isChecked: Bool = false {
        didSet {
            updateButtonImage(checkboxButton, isChecked: isChecked)
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
        
        isChecked = false
        
        checkboxButton.tintColor = .systemBlue
        checkboxButton.imageView?.contentMode = .scaleAspectFit
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
            checkboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        
        let label = UILabel()
        label.text = NSLocalizedString("Don't show this warning again", comment: "")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
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
        
        self.preferredContentSize = CGSize(width: 270, height: 36)
    }
    
    @objc func toggleCheckbox() {
        isChecked.toggle()
    }
}
