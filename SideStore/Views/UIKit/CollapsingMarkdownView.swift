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
        MarkdownParser(font: Self.Fonts.body)
    }
}

final class CollapsingMarkdownView: UIView {
    /// Called when the collapse state toggles.
    var didToggleCollapse: (() -> Void)?
        
    
    // MARK: - Properties
    var isCollapsed = true {
        didSet {
            guard self.isCollapsed != oldValue else { return }
            self.updateToggleButtonTitle()
            self.updateCollapsedState()
        }
    }
    
    var maximumNumberOfLines = 3 {
        didSet {
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
    
    private var needsCollapsing = false
    private func checkIfNeedsCollapsing() {
        let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let lineHeight = textView.font?.lineHeight ?? 0
        let actualLines = textSize.height / lineHeight
        
        needsCollapsing = actualLines > CGFloat(maximumNumberOfLines)
        
        // Hide toggle button if no collapsing needed
        toggleButton.isHidden = !needsCollapsing
    }
    
    private func updateCollapsedState() {
        // Disable animations for this update to prevent gradual rearrangement
        UIView.performWithoutAnimation {
            // Update the button title
            let title = isCollapsed ? NSLocalizedString("More", comment: "") : NSLocalizedString("Less", comment: "")
            toggleButton.setTitle(title, for: .normal)
            
            // Make sure toggle button is only visible when needed
            toggleButton.isHidden = !needsCollapsing
            
            // Update text view constraints
            if isCollapsed && needsCollapsing {
                textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
                
                // Create exclusion path for button
                let buttonSize = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000))
                let buttonY = (textView.font?.lineHeight ?? 0) * CGFloat(maximumNumberOfLines - 1)
                
                let exclusionFrame = CGRect(
                    x: bounds.width - buttonSize.width - 5, // Add some padding
                    y: buttonY,
                    width: buttonSize.width + 10, // Add padding around button
                    height: (textView.font?.lineHeight ?? 0) + 5
                )
                
                textView.textContainer.exclusionPaths = [UIBezierPath(rect: exclusionFrame)]
            } else {
                textView.textContainer.maximumNumberOfLines = 0
                textView.textContainer.exclusionPaths = []
            }
            
            // Force an immediate layout update
            textView.layoutIfNeeded()
            self.layoutIfNeeded()
            
            // Invalidate intrinsic content size to ensure proper sizing
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
        
        // Configure toggle button instead of more button
        toggleButton.addTarget(self, action: #selector(toggleCollapsed(_:)), for: .primaryActionTriggered)
        addSubview(toggleButton)
        
        // Update the button title based on current state
        updateToggleButtonTitle()
               
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
    }
    
    // Make sure this is called properly
    private func updateToggleButtonTitle() {
        let title = isCollapsed ? NSLocalizedString("More", comment: "") : NSLocalizedString("Less", comment: "")
        toggleButton.setTitle(title, for: .normal)
    }


    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        
        UIView.performWithoutAnimation {
            textView.frame = bounds
            
            // Check if content needs collapsing when layout changes
            if previousSize?.width != bounds.width {
                checkIfNeedsCollapsing()
                previousSize = bounds.size
            }
            
            // Only position toggle button if it's needed
            if !toggleButton.isHidden {
                let buttonSize = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000))
                
                if isCollapsed {
                    let buttonY = (textView.font?.lineHeight ?? 0) * CGFloat(maximumNumberOfLines - 1)
                    toggleButton.frame = CGRect(
                        x: bounds.width - buttonSize.width,
                        y: buttonY,
                        width: buttonSize.width,
                        height: textView.font?.lineHeight ?? 0
                    )
                } else {
                    // Position at the end of content when expanded
                    let textHeight = textView.sizeThatFits(bounds.size).height
                    let lineHeight = textView.font?.lineHeight ?? 0
                    toggleButton.frame = CGRect(
                        x: bounds.width - buttonSize.width,
                        y: textHeight - lineHeight,
                        width: buttonSize.width,
                        height: lineHeight
                    )
                }
            }
        }
    }
    
    @objc private func toggleCollapsed(_ sender: UIButton) {
        // Toggle the state instantly
        isCollapsed.toggle()
        
        // Update the UI without animation
        UIView.performWithoutAnimation {
            updateToggleButtonTitle()
            updateCollapsedState()
        }
        
        // Notify any observer that a toggle occurred
        didToggleCollapse?()
    }

    override var intrinsicContentSize: CGSize {
        if isCollapsed {
            guard let font = textView.font else { return super.intrinsicContentSize }
            let height = font.lineHeight * CGFloat(maximumNumberOfLines) + lineSpacing * CGFloat(maximumNumberOfLines - 1)
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        } else {
            // When expanded, use the full content size of the text view
            let size = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
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
