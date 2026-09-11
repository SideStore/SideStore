//
//  RevokeCertificatesAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 11/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
@preconcurrency import UIKit
import SideSign

class RevokeCertificatesAlertViewController: UIViewController {
    let certificates: [ALTX509Certificate]
    let teamType: ALTTeamType

    private(set) var selectedCertificates: Set<String> = []
    var onSelectionChanged: (([ALTX509Certificate]) -> Void)?

    init(certificates: [ALTX509Certificate], teamType: ALTTeamType) {
        self.certificates = certificates
        self.teamType = teamType
        super.init(nibName: nil, bundle: nil)

        if teamType == .free {
            for cert in certificates {
                selectedCertificates.insert(cert.serialNumber)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let isPaid = (teamType != .free)

        for (index, cert) in certificates.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.alignment = .center

            if isPaid {
                let checkboxButton = UIButton(type: .system)
                checkboxButton.tintColor = .systemRed
                checkboxButton.tag = index
                checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
                checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
                NSLayoutConstraint.activate([
                    checkboxButton.widthAnchor.constraint(equalToConstant: 24),
                    checkboxButton.heightAnchor.constraint(equalToConstant: 24)
                ])
                updateButtonImage(checkboxButton, isChecked: selectedCertificates.contains(cert.serialNumber))
                checkboxButton.addTarget(self, action: #selector(toggleCertCheckbox(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(checkboxButton)
            }

            let detailStack = UIStackView()
            detailStack.axis = .vertical
            detailStack.spacing = 2
            detailStack.alignment = .leading

            let titleLabel = UILabel()
            let certName = cert.machineName ?? cert.name
            titleLabel.text = "\(index + 1). \(certName)"
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .label
            titleLabel.numberOfLines = 1

            let serialLabel = UILabel()
            serialLabel.text = String(format: NSLocalizedString("Serial: %@", comment: ""), cert.serialNumber)
            serialLabel.font = .systemFont(ofSize: 11, weight: .regular)
            serialLabel.textColor = .secondaryLabel
            serialLabel.numberOfLines = 1

            let expLabel = UILabel()
            let expDate = cert.expiryDate != Date.distantPast ? ISO8601DateFormatter().string(from: cert.expiryDate) : NSLocalizedString("Unknown", comment: "")
            expLabel.text = String(format: NSLocalizedString("Expires: %@", comment: ""), String(expDate.prefix(10)))
            expLabel.font = .systemFont(ofSize: 11, weight: .regular)
            expLabel.textColor = .secondaryLabel
            expLabel.numberOfLines = 1

            detailStack.addArrangedSubview(titleLabel)
            detailStack.addArrangedSubview(serialLabel)
            detailStack.addArrangedSubview(expLabel)

            if isPaid {
                detailStack.isUserInteractionEnabled = true
                let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleRowTap(_:)))
                detailStack.addGestureRecognizer(tapGesture)
                detailStack.tag = index
            }

            rowStack.addArrangedSubview(detailStack)
            stackView.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -4),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16)
        ])

        let rowHeight: CGFloat = 54
        let totalHeight = CGFloat(certificates.count) * rowHeight + 12
        self.preferredContentSize = CGSize(width: 270, height: min(totalHeight, 200))
    }

    private func updateButtonImage(_ button: UIButton, isChecked: Bool) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        button.setImage(image, for: .normal)
    }

    @objc private func toggleCertCheckbox(_ sender: UIButton) {
        let index = sender.tag
        guard index < certificates.count else { return }
        let cert = certificates[index]

        if selectedCertificates.contains(cert.serialNumber) {
            selectedCertificates.remove(cert.serialNumber)
        } else {
            selectedCertificates.insert(cert.serialNumber)
        }

        updateButtonImage(sender, isChecked: selectedCertificates.contains(cert.serialNumber))

        let selected = getSelectedCertificates()
        onSelectionChanged?(selected)
    }

    @objc private func toggleRowTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view, let rowStack = view.superview as? UIStackView,
              let checkboxButton = rowStack.arrangedSubviews.first as? UIButton else { return }
        toggleCertCheckbox(checkboxButton)
    }

    func getSelectedCertificates() -> [ALTX509Certificate] {
        return certificates.filter { selectedCertificates.contains($0.serialNumber) }
    }
}
