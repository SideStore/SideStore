//
//  CollapsingMarkdownView.swift
//  AltStore
//
//  Created by Magesh K on 27/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import UIKit
import MarkdownKit

struct MarkdownManager
{
    struct Fonts{
        static let body: UIFont     = .systemFont(ofSize: UIFont.systemFontSize)
//        static let body: UIFont     = .systemFont(ofSize: UIFont.labelFontSize)
        
        static let header: UIFont   = .boldSystemFont(ofSize: 14)
        static let list: UIFont     = .systemFont(ofSize: 14)
        static let bold: UIFont     = .boldSystemFont(ofSize: 14)
        static let italic: UIFont   = .italicSystemFont(ofSize: 14)
        static let quote: UIFont    = .italicSystemFont(ofSize: 14)
    }
    
    struct Color{
        static let header = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        }
        static let bold = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor.lightText : UIColor.darkText
        }
    }
    
    static var enabledElements: MarkdownParser.EnabledElements {
        [
            .header,
            .list,
            .quote,
            .code,
            .link,
            .bold,
            .italic,
        ]
    }
    
    var markdownParser: MarkdownParser {
        MarkdownParser(
            font: Self.Fonts.body,
            color: Self.Color.bold
        )
    }
}
final class CollapsingMarkdownView: UIView {
    /// Called when the collapse state toggles.
    var didToggleCollapse: (() -> Void)?
    
    // MARK: - Properties
    var isCollapsed = true {
        didSet {
            guard self.isCollapsed != oldValue else { return }
            self.updateCollapsedState()
        }
    }
    
    var maximumNumberOfLines = 3 {
        didSet {
            self.checkIfNeedsCollapsing()
            self.updateCollapsedState()
            self.setNeedsLayout()
        }
    }
    
    var text: String = "" {
        didSet {
            self.updateMarkdownContent()
            self.setNeedsLayout()
        }
    }
    
    var lineSpacing: Double = 2 {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    let toggleButton = UIButton(type: .system)
    
    private let textView = UITextView()
    private let markdownParser = MarkdownManager().markdownParser
    
    private var previousSize: CGSize?
    private var actualLineCount: Int = 0
    private var needsCollapsing = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        initialize()
    }
    
    private func checkIfNeedsCollapsing() {
        guard bounds.width > 0, let font = textView.font, font.lineHeight > 0 else {
            needsCollapsing = false
            return
        }
        
        // Calculate the number of lines in the text
        let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let lineHeight = font.lineHeight
        
        // Safely calculate actual line count
        actualLineCount = max(1, Int(ceil(textSize.height / lineHeight)))
        
        // Only needs collapsing if actual lines exceed the maximum
        needsCollapsing = actualLineCount > maximumNumberOfLines
        
        // Update button visibility
        toggleButton.isHidden = !needsCollapsing
    }
    
    private func updateCollapsedState() {
        // Disable animations for this update
        UIView.performWithoutAnimation {
            // Update the button title
            let title = isCollapsed ? NSLocalizedString("More", comment: "") : NSLocalizedString("Less", comment: "")
            toggleButton.setTitle(title, for: .normal)
            
            // Set max lines based on collapsed state
            if isCollapsed && needsCollapsing {
                textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
            } else {
                textView.textContainer.maximumNumberOfLines = 0
            }
            
            // Button is only visible if content needs collapsing
            toggleButton.isHidden = !needsCollapsing
            
            // Force layout updates
            textView.layoutIfNeeded()
            self.layoutIfNeeded()
            self.invalidateIntrinsicContentSize()
        }
    }
    
    private func initialize() {
        // Configure text view
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.backgroundColor = .clear

        // Make textView selectable to enable link interactions
        textView.isSelectable = true
        textView.delegate = self
        
        // Important: This prevents selection handles from appearing
        textView.dataDetectorTypes = .link
    
        // Configure markdown parser
        configureMarkdownParser()
        
        // Add subviews
        addSubview(textView)
        
        // Configure toggle button
        toggleButton.addTarget(self, action: #selector(toggleCollapsed(_:)), for: .primaryActionTriggered)
        addSubview(toggleButton)
        
        setNeedsLayout()
    }

    private func configureMarkdownParser() {
        // Configure markdown parser with desired settings
        markdownParser.enabledElements = MarkdownManager.enabledElements
        
        // You can also customize the styling if needed
        markdownParser.header.font = MarkdownManager.Fonts.header
        markdownParser.list.font = MarkdownManager.Fonts.list
        markdownParser.bold.font = MarkdownManager.Fonts.bold
        markdownParser.italic.font = MarkdownManager.Fonts.italic
        markdownParser.quote.font = MarkdownManager.Fonts.quote
        
        markdownParser.header.color = MarkdownManager.Color.header
        markdownParser.bold.color =  MarkdownManager.Color.bold
        markdownParser.list.color =  MarkdownManager.Color.bold
    }
    
    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        
        UIView.performWithoutAnimation {
            // Calculate button height (for spacing)
            let buttonHeight = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000)).height
            
            // Set textView frame to leave space for button
            textView.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: bounds.height - buttonHeight
            )
            
            // Check if layout changed
            if previousSize?.width != bounds.width {
                checkIfNeedsCollapsing()
                updateCollapsedState()
                previousSize = bounds.size
            }
            
            // Position toggle button at bottom right
            let buttonSize = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000))
            toggleButton.frame = CGRect(
                x: bounds.width - buttonSize.width,
                y: textView.frame.maxY,
                width: buttonSize.width,
                height: buttonHeight
            )
        }
    }
    
    @objc private func toggleCollapsed(_ sender: UIButton) {
        isCollapsed.toggle()
        didToggleCollapse?()
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0, let font = textView.font, font.lineHeight > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        
        let lineHeight = font.lineHeight
        let buttonHeight = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000)).height
        
        // Always add button height to reserve space for it
        if isCollapsed && needsCollapsing {
            // When collapsed and needs collapsing, use maximumNumberOfLines
            let collapsedHeight = lineHeight * CGFloat(maximumNumberOfLines) + 
                             lineSpacing * CGFloat(max(0, maximumNumberOfLines - 1))
            return CGSize(width: UIView.noIntrinsicMetric, height: collapsedHeight + buttonHeight)
        } else if !needsCollapsing {
            // Text is shorter than max lines - use actual text height
            let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: textSize.height + buttonHeight)
        } else {
            // When expanded and needs collapsing, use full text height plus button
            let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: textSize.height + buttonHeight)
        }
    }

    // MARK: - Markdown Processing
    private func updateMarkdownContent() {
        let attributedString = markdownParser.parse(text)
        
        // Apply line spacing
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        
        mutableAttributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutableAttributedString.length)
        )
        
        textView.attributedText = mutableAttributedString
        
        // Check if content needs collapsing after setting text
        checkIfNeedsCollapsing()
        updateCollapsedState()
    }
}

extension CollapsingMarkdownView: UITextViewDelegate {
    // This enables tapping on links while preventing text selection
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Open the URL using UIApplication
        UIApplication.shared.open(URL)
        return false // Return false to prevent the default behavior
    }
    
    // This prevents text selection
    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }
}
