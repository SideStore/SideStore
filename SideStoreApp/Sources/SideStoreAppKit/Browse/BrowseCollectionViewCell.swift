//
//  BrowseCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import RoxasUIKit
import os.log

import Nuke

@objc final class BrowseCollectionViewCell: UICollectionViewCell {
    var imageURLs: [URL] = [] {
        didSet {
            dataSource.items = imageURLs as [NSURL]
        }
    }

    private lazy var dataSource = self.makeDataSource()

    @IBOutlet var bannerView: AppBannerView!
    @IBOutlet var subtitleLabel: UILabel!

    @IBOutlet private(set) var screenshotsCollectionView: UICollectionView!

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.preservesSuperviewLayoutMargins = true

        // Must be registered programmatically, not in BrowseCollectionViewCell.xib, or else it'll throw an exception 🤷‍♂️.
        screenshotsCollectionView.register(ScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)

        screenshotsCollectionView.delegate = self
        screenshotsCollectionView.dataSource = dataSource
        screenshotsCollectionView.prefetchDataSource = dataSource
    }
}

private extension BrowseCollectionViewCell {
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage> {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { cell, _, _ in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { imageURL, _, completionHandler in
            RSTAsyncBlockOperation { operation in
                let request = ImageRequest(url: imageURL as URL, processor: .screenshot)
                ImagePipeline.shared.loadImage(with: request, progress: nil, completion: { response, error in
                    guard !operation.isCancelled else { return operation.finish() }

                    if let image = response?.image {
                        completionHandler(image, nil)
                    } else {
                        completionHandler(nil, error)
                    }
                })
            }
        }
        dataSource.prefetchCompletionHandler = { cell, image, _, error in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image

            if let error = error {
                os_log("Error loading image: %@", type: .error , error.localizedDescription)
            }
        }

        return dataSource
    }
}

extension BrowseCollectionViewCell: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt _: IndexPath) -> CGSize {
        // Assuming 9.0 / 16.0 ratio for now.
        let aspectRatio: CGFloat = 9.0 / 16.0

        let itemHeight = collectionView.bounds.height
        let itemWidth = itemHeight * aspectRatio

        let size = CGSize(width: itemWidth.rounded(.down), height: itemHeight.rounded(.down))
        return size
    }
}
