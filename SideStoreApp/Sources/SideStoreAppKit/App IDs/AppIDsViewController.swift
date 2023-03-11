//
//  AppIDsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore
import RoxasUIKit
import Down

final class AppIDsViewController: UICollectionViewController {
    private lazy var dataSource = self.makeDataSource()

    private var didInitialFetch = false
    private var isLoading = false {
        didSet {
            update()
        }
    }

    @IBOutlet var activityIndicatorBarButtonItem: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.dataSource = dataSource

        activityIndicatorBarButtonItem.isIndicatingActivity = true

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(AppIDsViewController.fetchAppIDs), for: .primaryActionTriggered)
        collectionView.refreshControl = refreshControl
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !didInitialFetch {
            fetchAppIDs()
        }
    }
}

private extension AppIDsViewController {
    func makeDataSource() -> RSTFetchedResultsCollectionViewDataSource<AppID> {
        let fetchRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AppID.name, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.bundleIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.expirationDate, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false

        if let team = DatabaseManager.shared.activeTeam() {
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(AppID.team), team)
        } else {
            fetchRequest.predicate = NSPredicate(value: false)
        }

        let dataSource = RSTFetchedResultsCollectionViewDataSource<AppID>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { cell, appID, _ in
            let tintColor = UIColor.altPrimary

            let cell = cell as! BannerCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor

            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false

            cell.bannerView.buttonLabel.text = NSLocalizedString("Expires in", comment: "")

            let attributedAccessibilityLabel = NSMutableAttributedString(string: appID.name + ". ")

            if let expirationDate = appID.expirationDate {
                cell.bannerView.button.isHidden = false
                cell.bannerView.button.isUserInteractionEnabled = false

                cell.bannerView.buttonLabel.isHidden = false

                let currentDate = Date()

                let numberOfDays = expirationDate.numberOfCalendarDays(since: currentDate)
                let numberOfDaysText = (numberOfDays == 1) ? NSLocalizedString("1 day", comment: "") : String(format: NSLocalizedString("%@ days", comment: ""), NSNumber(value: numberOfDays))
                cell.bannerView.button.setTitle(numberOfDaysText.uppercased(), for: .normal)

                attributedAccessibilityLabel.mutableString.append(String(format: NSLocalizedString("Expires in %@.", comment: ""), numberOfDaysText) + " ")
            } else {
                cell.bannerView.button.isHidden = true
                cell.bannerView.button.isUserInteractionEnabled = true

                cell.bannerView.buttonLabel.isHidden = true
            }

            cell.bannerView.titleLabel.text = appID.name
            cell.bannerView.subtitleLabel.text = appID.bundleIdentifier
            cell.bannerView.subtitleLabel.numberOfLines = 2

            let attributedBundleIdentifier = NSMutableAttributedString(string: appID.bundleIdentifier.lowercased(), attributes: [.accessibilitySpeechPunctuation: true])

            if let team = appID.team, let range = attributedBundleIdentifier.string.range(of: team.identifier.lowercased()), #available(iOS 13, *) {
                // Prefer to speak the team ID one character at a time.
                let nsRange = NSRange(range, in: attributedBundleIdentifier.string)
                attributedBundleIdentifier.addAttributes([.accessibilitySpeechSpellOut: true], range: nsRange)
            }

            attributedAccessibilityLabel.append(attributedBundleIdentifier)
            cell.bannerView.accessibilityAttributedLabel = attributedAccessibilityLabel

            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }

        return dataSource
    }

    @objc func fetchAppIDs() {
        guard !isLoading else { return }
        isLoading = true

        AppManager.shared.fetchAppIDs { result in
            do {
                let (_, context) = try result.get()
                try context.save()
            } catch {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }

            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }

    func update() {
        if !isLoading {
            collectionView.refreshControl?.endRefreshing()
            activityIndicatorBarButtonItem.isIndicatingActivity = false
        }
    }
}

extension AppIDsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt _: IndexPath) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 80)
    }

    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let indexPath = IndexPath(row: 0, section: section)
        let headerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader, at: indexPath)

        // Use this view to calculate the optimal size based on the collection view's width
        let size = headerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
                                                      withHorizontalFittingPriority: .required, // Width is fixed
                                                      verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
        return size
    }

    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, referenceSizeForFooterInSection _: Int) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 50)
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! TextCollectionReusableView
            headerView.layoutMargins.left = view.layoutMargins.left
            headerView.layoutMargins.right = view.layoutMargins.right

            if let activeTeam = DatabaseManager.shared.activeTeam(), activeTeam.type == .free {
                let text = NSLocalizedString(
				"""
                Each app and app extension installed with SideStore must register an App ID with Apple. Apple limits non-developer Apple IDs to 10 App IDs at a time.

                **App IDs can't be deleted**, but they do expire after one week. SideStore will automatically renew App IDs for all active apps once they've expired.
                """, comment: "")

				let mdown = Down(markdownString: text)
				let labelFont: DownFont = headerView.textLabel.font
				let fonts: FontCollection = StaticFontCollection(
					heading1: labelFont,
					heading2: labelFont,
					heading3: labelFont,
					heading4: labelFont,
					heading5: labelFont,
					heading6: labelFont,
					body: labelFont,
					code: labelFont,
					listItemPrefix: labelFont)
				let config: DownStylerConfiguration = .init(fonts: fonts)
				let styler: Styler = DownStyler.init(configuration: config)
				let options: DownOptions = .default
				headerView.textLabel.attributedText = try? mdown.toAttributedString(options,
																					styler: styler) ?? NSAttributedString(string: text)
			} else {
                headerView.textLabel.text = NSLocalizedString("""
                Each app and app extension installed with SideStore must register an App ID with Apple.

                App IDs for paid developer accounts never expire, and there is no limit to how many you can create.
                """, comment: "")
            }

            return headerView

        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Footer", for: indexPath) as! TextCollectionReusableView

            let count = dataSource.itemCount
            if count == 1 {
                footerView.textLabel.text = NSLocalizedString("1 App ID", comment: "")
            } else {
                footerView.textLabel.text = String(format: NSLocalizedString("%@ App IDs", comment: ""), NSNumber(value: count))
            }

            return footerView

        default: fatalError()
        }
    }
}

fileprivate enum MarkdownStyledBlock: Equatable {
	case generic
	case headline(Int)
	case paragraph
	case unorderedListElement
	case orderedListElement(Int)
	case blockquote
	case code(String?)
}

// MARK: -
@available(iOS 15, *)
extension AttributedString {

	init(styledMarkdown markdownString: String, fontSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize) throws {

		var s = try AttributedString(markdown: markdownString, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible, languageCode: "en"), baseURL: nil)

		// Looking at the AttributedString’s raw structure helps with understanding the following code.
		print(s)

		// Set base font and paragraph style for the whole string
		s.font = .systemFont(ofSize: fontSize)
		s.paragraphStyle = defaultParagraphStyle

		// Will respect dark mode automatically
		s.foregroundColor = .label

		// MARK: Inline Intents
		let inlineIntents: [InlinePresentationIntent] = [.emphasized, .stronglyEmphasized, .code, .strikethrough, .softBreak, .lineBreak, .inlineHTML, .blockHTML]

		for inlineIntent in inlineIntents {

			var sourceAttributeContainer = AttributeContainer()
			sourceAttributeContainer.inlinePresentationIntent = inlineIntent

			var targetAttributeContainer = AttributeContainer()
			switch inlineIntent {
			case .emphasized:
				targetAttributeContainer.font = .italicSystemFont(ofSize: fontSize)
			case .stronglyEmphasized:
				targetAttributeContainer.font = .systemFont(ofSize: fontSize, weight: .bold)
			case .code:
				targetAttributeContainer.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
				targetAttributeContainer.backgroundColor = .secondarySystemBackground
			case .strikethrough:
				targetAttributeContainer.strikethroughStyle = .single
			case .softBreak:
				break // TODO: Implement
			case .lineBreak:
				break // TODO: Implement
			case .inlineHTML:
				break // TODO: Implement
			case .blockHTML:
				break // TODO: Implement
			default:
				break
			}

			s = s.replacingAttributes(sourceAttributeContainer, with: targetAttributeContainer)
		}

		// MARK: Blocks
		// Accessing via dynamic lookup key path (\.presentationIntent) triggers a warning on Xcode 13.1, so we use the verbose way: AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
		// We use .reversed() iteration to be able to add characters to the string without breaking ranges.
		var previousListID = 0

		for (intentBlock, intentRange) in s.runs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self].reversed() {
			guard let intentBlock = intentBlock else { continue }

			var block: MarkdownStyledBlock = .generic
			var currentElementOrdinal: Int = 0

			var currentListID = 0

			for intent in intentBlock.components {
				switch intent.kind {
				case .paragraph:
					if block == .generic {
						block = .paragraph
					}
				case .header(level: let level):
					block = .headline(level)
				case .orderedList:
					block = .orderedListElement(currentElementOrdinal)
					currentListID = intent.identity
				case .unorderedList:
					block = .unorderedListElement
					currentListID = intent.identity
				case .listItem(ordinal: let ordinal):
					currentElementOrdinal = ordinal
					if block != .unorderedListElement {
						block = .orderedListElement(ordinal)
					}
				case .codeBlock(languageHint: let languageHint):
					block = .code(languageHint)
				case .blockQuote:
					block = .blockquote
				case .thematicBreak:
					break // This is ---- in Markdown.
				case .table(columns: _):
					break
				case .tableHeaderRow:
					break
				case .tableRow(rowIndex: _):
					break
				case .tableCell(columnIndex: _):
					break
				@unknown default:
					break
				}
			}

			switch block {
			case .generic:
				assertionFailure(intentBlock.debugDescription)
			case .headline(let level):
				switch level {
				case 1:
					s[intentRange].font = .systemFont(ofSize: 30, weight: .heavy)
				case 2:
					s[intentRange].font = .systemFont(ofSize: 20, weight: .heavy)
				case 3:
					s[intentRange].font = .systemFont(ofSize: 15, weight: .heavy)
				default:
					// TODO: Handle H4 to H6
					s[intentRange].font = .systemFont(ofSize: 15, weight: .heavy)
				}
			case .paragraph:
				break
			case .unorderedListElement:
				s.characters.insert(contentsOf: "•\t", at: intentRange.lowerBound)
				s[intentRange].paragraphStyle = previousListID == currentListID ? listParagraphStyle : lastElementListParagraphStyle
			case .orderedListElement(let ordinal):
				s.characters.insert(contentsOf: "\(ordinal).\t", at: intentRange.lowerBound)
				s[intentRange].paragraphStyle = previousListID == currentListID ? listParagraphStyle : lastElementListParagraphStyle
			case .blockquote:
				s[intentRange].paragraphStyle = defaultParagraphStyle
				s[intentRange].foregroundColor = .secondaryLabel
			case .code:
				s[intentRange].font = .monospacedSystemFont(ofSize: 13, weight: .regular)
				s[intentRange].paragraphStyle = codeParagraphStyle
			}

			// Remember the list ID so we can check if it’s identical in the next block
			previousListID = currentListID

			// MARK: Add line breaks to separate blocks
			if intentRange.lowerBound != s.startIndex {
				s.characters.insert(contentsOf: "\n", at: intentRange.lowerBound)
			}
		}

		self = s
	}
}

fileprivate let defaultParagraphStyle: NSParagraphStyle = {
	var paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.paragraphSpacing = 10.0
	paragraphStyle.minimumLineHeight = 20.0
	return paragraphStyle
}()


fileprivate let listParagraphStyle: NSMutableParagraphStyle = {
	var paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
	paragraphStyle.headIndent = 20
	paragraphStyle.minimumLineHeight = 20.0
	return paragraphStyle
}()

fileprivate let lastElementListParagraphStyle: NSMutableParagraphStyle = {
	var paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
	paragraphStyle.headIndent = 20
	paragraphStyle.minimumLineHeight = 20.0
	paragraphStyle.paragraphSpacing = 20.0 // The last element in a list needs extra paragraph spacing
	return paragraphStyle
}()


fileprivate let codeParagraphStyle: NSParagraphStyle = {
	var paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.minimumLineHeight = 20.0
	paragraphStyle.firstLineHeadIndent = 20
	paragraphStyle.headIndent = 20
	return paragraphStyle
}()
