//
//  WebCollectionViewController.swift
//  SideStore
//
//  Created by mantou on 2025/2/17.
//  Copyright © 2025 SideStore. All rights reserved.
//

import UIKit
import WebKit

class WebCollectionViewController: UICollectionViewController {
    private let webViewURLString = "https://ipa.cloudmantoub.online"

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = view.bounds.size
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        collectionView.collectionViewLayout = layout
        
        // 忽略安全区域
        collectionView.contentInsetAdjustmentBehavior = .never
        
        collectionView.isPagingEnabled = false
        collectionView.isScrollEnabled = false
        collectionView.register(WebViewCell.self, forCellWithReuseIdentifier: "WebViewCell")
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "WebViewCell", for: indexPath) as! WebViewCell
        cell.loadURL(webViewURLString)
        return cell
    }
}

class WebViewCell: UICollectionViewCell {
    private var webView: WKWebView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWebView() {
        webView = WKWebView(frame: .zero)
        contentView.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
        ])
    }

    func loadURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}
