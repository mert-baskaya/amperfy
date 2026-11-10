//
//  LyricTableCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 17.06.24.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AmperfyKit
import CoreData
import UIKit

// MARK: - LyricTableCellModel

@MainActor
class LyricTableCellModel {
  var lyric: LyricsLine? {
    didSet {
      cell?.refresh()
    }
  }

  var isActiveLine = false {
    didSet {
      cell?.refresh()
    }
  }

  /// The sung part of the active line. Only used if the line has word timing.
  var wordProgress: LyricsCueProgress? {
    didSet {
      guard oldValue != wordProgress else { return }
      cell?.refreshWordProgress()
    }
  }

  /// The held word of the active line that is drawn with emphasis
  var wordEmphasis: LyricsCueEmphasis? {
    didSet {
      guard oldValue != wordEmphasis else { return }
      cell?.refreshWordProgress()
    }
  }

  /// The sung part of the background voice of the active line
  var backgroundProgress: LyricsCueProgress? {
    didSet {
      guard oldValue != backgroundProgress else { return }
      cell?.refreshWordProgress()
    }
  }

  /// The cue line of the main agent, if its cues were found in the line text
  let cueLine: LyricsCueLine?
  /// The range (NSString) of each cue in the line text
  let cueRanges: [NSRange]
  /// The background voice of the line. Its text is drawn small, below the text of the main voice.
  let backgroundCueLine: LyricsCueLine?
  let backgroundCueRanges: [NSRange]
  /// The side of the line in a duet
  let side: LyricsLineSide

  private var attributedString: NSAttributedString?
  private var highlightedAttributedString: NSAttributedString?
  private var unsungAttributedString: NSAttributedString?
  private var backgroundAttributedString: NSAttributedString?
  private var backgroundSungAttributedString: NSAttributedString?

  internal weak var cell: LyricTableCell?

  private static let backgroundSpacing: CGFloat = 2
  /// A duet line leaves room on the other side
  private static let duetWidthFactor: CGFloat = 0.85

  private var isWordHighlightActive: Bool {
    isActiveLine && cueLine != nil
  }

  var displayString: NSAttributedString? {
    guard isActiveLine else { return attributedString }
    return isWordHighlightActive ? unsungAttributedString : highlightedAttributedString
  }

  /// Drawn over the display string. Only the sung part of it is visible.
  var sungString: NSAttributedString? {
    isWordHighlightActive ? highlightedAttributedString : nil
  }

  var backgroundDisplayString: NSAttributedString? {
    backgroundAttributedString
  }

  /// Drawn over the background display string. Only the sung part of it is visible.
  var backgroundSungString: NSAttributedString? {
    isActiveLine ? backgroundSungAttributedString : nil
  }

  init(
    lyric: LyricsLine,
    cueLine: LyricsCueLine? = nil,
    backgroundCueLine: LyricsCueLine? = nil,
    side: LyricsLineSide = .center
  ) {
    self.lyric = lyric
    self.isActiveLine = false
    self.side = side
    var text = lyric.value
    var backgroundText: String?
    if let backgroundCueLine, let split = backgroundCueLine.splitBackground(of: lyric.value),
       let ranges = backgroundCueLine.cueRanges(in: split.background) {
      text = split.main
      backgroundText = split.background
      self.backgroundCueLine = backgroundCueLine
      self.backgroundCueRanges = ranges.map { NSRange($0, in: split.background) }
    } else {
      self.backgroundCueLine = nil
      self.backgroundCueRanges = []
    }
    if let cueLine, let ranges = cueLine.cueRanges(in: text) {
      self.cueLine = cueLine
      self.cueRanges = ranges.map { NSRange($0, in: text) }
    } else {
      self.cueLine = nil
      self.cueRanges = []
    }
    let paragraphStyle = NSMutableParagraphStyle()
    switch side {
    case .center: paragraphStyle.alignment = .center
    case .leading: paragraphStyle.alignment = .left
    case .trailing: paragraphStyle.alignment = .right
    }
    paragraphStyle.lineBreakMode = .byWordWrapping
    self.attributedString = NSAttributedString(
      string: text,
      attributes:
      [
        .font: UIFont.systemFont(ofSize: 20),
        .foregroundColor: UIColor.gray,
        .paragraphStyle: paragraphStyle,
      ]
    )
    self.highlightedAttributedString = NSAttributedString(
      string: text,
      attributes:
      [
        .font: UIFont.boldSystemFont(ofSize: 20),
        .foregroundColor: UIColor.label,
        .paragraphStyle: paragraphStyle,
      ]
    )
    if self.cueLine != nil {
      self.unsungAttributedString = NSAttributedString(
        string: text,
        attributes:
        [
          .font: UIFont.boldSystemFont(ofSize: 20),
          .foregroundColor: UIColor.gray,
          .paragraphStyle: paragraphStyle,
        ]
      )
    }
    if let backgroundText {
      // the same font for both states: the height of the background text does not change
      let backgroundFont = UIFont.systemFont(ofSize: 15, weight: .medium)
      self.backgroundAttributedString = NSAttributedString(
        string: backgroundText,
        attributes:
        [
          .font: backgroundFont,
          .foregroundColor: UIColor.gray,
          .paragraphStyle: paragraphStyle,
        ]
      )
      self.backgroundSungAttributedString = NSAttributedString(
        string: backgroundText,
        attributes:
        [
          .font: backgroundFont,
          .foregroundColor: UIColor.label.withAlphaComponent(0.8),
          .paragraphStyle: paragraphStyle,
        ]
      )
    }
  }

  /// The width of the text in a cell of the container width
  func textWidth(containerWidth: CGFloat) -> CGFloat {
    LyricTableCell.adjustContainerWidthForMargins(containerWidth: containerWidth)
      * (side == .center ? 1 : Self.duetWidthFactor)
  }

  public func calcHeight(containerWidth: CGFloat) -> CGFloat {
    mainHeight(containerWidth: containerWidth) + backgroundHeight(containerWidth: containerWidth)
  }

  func mainHeight(containerWidth: CGFloat) -> CGFloat {
    height(
      of: isActiveLine ? highlightedAttributedString : attributedString,
      containerWidth: containerWidth
    )
  }

  func backgroundHeight(containerWidth: CGFloat) -> CGFloat {
    guard let backgroundAttributedString else { return 0 }
    return ceil(height(of: backgroundAttributedString, containerWidth: containerWidth))
      + Self.backgroundSpacing
  }

  private func height(of text: NSAttributedString?, containerWidth: CGFloat) -> CGFloat {
    text?.boundingRect(
      with: CGSize(width: textWidth(containerWidth: containerWidth), height: 9_999),
      options: .usesLineFragmentOrigin,
      context: nil
    ).height ?? 0
  }
}

// MARK: - LyricTableCell

class LyricTableCell: UITableViewCell {
  private weak var viewModel: LyricTableCellModel? = nil

  private var lyricView: LyricTextView!
  /// The active line in its full color, masked to the sung words
  private var sungLyricView: LyricTextView!
  private let sungMask = CAShapeLayer()
  private var backgroundLyricView: LyricTextView!
  private var backgroundSungLyricView: LyricTextView!
  private let backgroundSungMask = CAShapeLayer()
  /// The emphasized word, lifted out of the line: its unsung text and, with a glow, its sung part
  private let emphasisView = UIView()
  /// A tight glow inside a wide halo
  private let emphasisHaloView = UIView()
  private let emphasisGlowView = UIView()
  private var emphasisUnsungView: LyricTextView!
  private var emphasisSungView: LyricTextView!
  private let emphasisUnsungMask = CAShapeLayer()
  private let emphasisSungMask = CAShapeLayer()
  /// Hides the emphasized word in the line
  private let lyricMask = CAShapeLayer()
  private static let emphasisScale = 0.06
  private static let emphasisLift = 2.0
  private static let emphasisGlowOpacity = 1.0
  private static let emphasisHaloOpacity = 0.8
  /// A dark glow on dark text smears the word: keep it faint in light mode
  private static let emphasisLightModeGlowFactor = 0.3
  override var layoutMargins: UIEdgeInsets { get { BasicTableCell.margin } set {} }

  static func adjustContainerWidthForMargins(containerWidth: CGFloat) -> CGFloat {
    containerWidth - (2 * BasicTableCell.margin.right)
  }

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    commonInit()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  /// The frame of the main text. A duet line is on its side of the cell.
  private var textFrame: CGRect {
    let availableWidth = bounds.width - (2 * layoutMargins.right)
    let width = viewModel?.textWidth(containerWidth: bounds.width) ?? availableWidth
    var x = layoutMargins.left
    switch viewModel?.side ?? .center {
    case .center: x += (availableWidth - width) / 2
    case .leading: break
    case .trailing: x += availableWidth - width
    }
    let backgroundHeight = viewModel?.backgroundHeight(containerWidth: bounds.width) ?? 0
    return CGRect(x: x, y: 0, width: width, height: bounds.height - backgroundHeight)
  }

  /// The frame of the background text, directly below the main text
  private var backgroundTextFrame: CGRect {
    guard let model = viewModel else { return .zero }
    let frame = textFrame
    let backgroundHeight = model.backgroundHeight(containerWidth: bounds.width)
    let mainHeight = model.mainHeight(containerWidth: bounds.width)
    let padding = max((bounds.height - mainHeight - backgroundHeight) / 2, 0)
    return CGRect(
      x: frame.minX,
      y: bounds.height - padding - backgroundHeight,
      width: frame.width,
      height: backgroundHeight
    )
  }

  private func commonInit() {
    lyricView = LyricTextView(frame: textFrame)
    sungLyricView = LyricTextView(frame: textFrame)
    sungLyricView.isHidden = true
    sungLyricView.isAccessibilityElement = false
    sungLyricView.layer.mask = sungMask
    backgroundLyricView = LyricTextView(frame: .zero)
    backgroundLyricView.isHidden = true
    backgroundSungLyricView = LyricTextView(frame: .zero)
    backgroundSungLyricView.isHidden = true
    backgroundSungLyricView.isAccessibilityElement = false
    backgroundSungLyricView.layer.mask = backgroundSungMask
    lyricMask.fillRule = .evenOdd
    emphasisUnsungView = LyricTextView(frame: textFrame)
    emphasisUnsungView.isAccessibilityElement = false
    emphasisUnsungView.layer.mask = emphasisUnsungMask
    emphasisSungView = LyricTextView(frame: textFrame)
    emphasisSungView.isAccessibilityElement = false
    emphasisSungView.layer.mask = emphasisSungMask
    emphasisGlowView.layer.shadowOffset = .zero
    emphasisGlowView.layer.shadowRadius = 4
    emphasisGlowView.addSubview(emphasisSungView)
    emphasisHaloView.layer.shadowOffset = .zero
    emphasisHaloView.layer.shadowRadius = 12
    emphasisHaloView.addSubview(emphasisGlowView)
    emphasisView.isUserInteractionEnabled = false
    emphasisView.isHidden = true
    emphasisView.addSubview(emphasisUnsungView)
    emphasisView.addSubview(emphasisHaloView)
    selectionStyle = .none
    contentView.addSubview(lyricView)
    contentView.addSubview(sungLyricView)
    contentView.addSubview(backgroundLyricView)
    contentView.addSubview(backgroundSungLyricView)
    contentView.addSubview(emphasisView)
    backgroundColor = .clear
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutTextViews()
    refreshWordProgress()
  }

  private func layoutTextViews() {
    lyricView.frame = textFrame
    sungLyricView.frame = textFrame
    backgroundLyricView.frame = backgroundTextFrame
    backgroundSungLyricView.frame = backgroundTextFrame
    // the emphasis view has a transform: its frame must not be set
    let textBounds = CGRect(origin: .zero, size: textFrame.size)
    emphasisView.bounds = textBounds
    emphasisView.center = CGPoint(x: textFrame.midX, y: textFrame.midY)
    emphasisUnsungView.frame = textBounds
    emphasisHaloView.frame = textBounds
    emphasisGlowView.frame = textBounds
    emphasisSungView.frame = textBounds
  }

  func display(model: LyricTableCellModel) {
    viewModel = model
    model.cell = self
    layoutTextViews()
    refresh()
  }

  func refresh() {
    guard let model = viewModel else { return }
    lyricView.attributedText = model.displayString
    sungLyricView.attributedText = model.sungString
    sungLyricView.isHidden = (model.sungString == nil)
    backgroundLyricView.attributedText = model.backgroundDisplayString
    backgroundLyricView.isHidden = (model.backgroundDisplayString == nil)
    backgroundSungLyricView.attributedText = model.backgroundSungString
    backgroundSungLyricView.isHidden = (model.backgroundSungString == nil)
    refreshWordProgress()
  }

  /// Moves the mask of the sung words. Called for each display frame while a line is sung.
  func refreshWordProgress() {
    guard let model = viewModel else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    let emphasis = sungLyricView.isHidden ? nil : model.wordEmphasis
    let emphasizedRange = emphasis.flatMap { model.cueRanges.object(at: $0.cueIndex) }
    refreshEmphasis(model: model, emphasis: emphasis, range: emphasizedRange)
    if !backgroundSungLyricView.isHidden {
      backgroundSungMask.frame = backgroundSungLyricView.bounds
      backgroundSungMask.path = backgroundSungLyricView.sungPath(
        cueRanges: model.backgroundCueRanges,
        progress: model.backgroundProgress
      )
    }
    guard !sungLyricView.isHidden else { return }
    sungMask.frame = sungLyricView.bounds
    sungMask.path = sungLyricView.sungPath(
      cueRanges: model.cueRanges,
      progress: model.wordProgress,
      excludedCueIndex: emphasizedRange != nil ? emphasis?.cueIndex : nil
    )
  }

  private func refreshEmphasis(
    model: LyricTableCellModel,
    emphasis: LyricsCueEmphasis?,
    range: NSRange?
  ) {
    guard let emphasis, let range else {
      if !emphasisView.isHidden {
        emphasisView.isHidden = true
        emphasisView.transform = .identity
        emphasisUnsungView.attributedText = nil
        emphasisSungView.attributedText = nil
        lyricView.layer.mask = nil
      }
      return
    }
    emphasisUnsungView.attributedText = model.displayString
    emphasisSungView.attributedText = model.sungString
    emphasisView.isHidden = false

    let wordRects = sungLyricView.rects(forCharacterRange: range)
    let wordPath = CGMutablePath()
    wordRects.forEach { wordPath.addRect($0) }
    let linePath = CGMutablePath()
    linePath.addRect(lyricView.bounds)
    linePath.addPath(wordPath)
    lyricMask.frame = lyricView.bounds
    lyricMask.path = linePath
    lyricView.layer.mask = lyricMask
    emphasisUnsungMask.frame = emphasisUnsungView.bounds
    emphasisUnsungMask.path = wordPath
    let isSung = model.wordProgress?.cueIndex != emphasis.cueIndex
    emphasisSungMask.frame = emphasisSungView.bounds
    emphasisSungMask.path = sungLyricView.partialPath(
      forCharacterRange: range,
      fraction: isSung ? 1 : (model.wordProgress?.fraction ?? 1)
    )

    // ease in and out
    let amount = emphasis.amount * emphasis.amount * (3 - 2 * emphasis.amount)
    let wordRect = wordRects.reduce(CGRect.null) { $0.union($1) }
    let dx = wordRect.midX - emphasisView.bounds.midX
    let dy = wordRect.midY - emphasisView.bounds.midY
    let scale = 1 + Self.emphasisScale * amount
    // scale around the center of the word
    emphasisView.transform = CGAffineTransform(
      translationX: dx,
      y: dy - Self.emphasisLift * amount
    )
    .scaledBy(x: scale, y: scale)
    .translatedBy(x: -dx, y: -dy)
    let glowColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
    let glowAmount = amount
      * (traitCollection.userInterfaceStyle == .dark ? 1 : Self.emphasisLightModeGlowFactor)
    emphasisGlowView.layer.shadowColor = glowColor
    emphasisGlowView.layer.shadowOpacity = Float(Self.emphasisGlowOpacity * glowAmount)
    emphasisHaloView.layer.shadowColor = glowColor
    emphasisHaloView.layer.shadowOpacity = Float(Self.emphasisHaloOpacity * glowAmount)
  }
}

// MARK: - LyricTextView

/// Draws a text with TextKit, centered in its bounds. The same layout gives the area of the sung words,
/// so a mask made from that area matches the drawn glyphs exactly.
class LyricTextView: UIView {
  var attributedText: NSAttributedString? {
    didSet {
      guard attributedText != oldValue else { return }
      textStorage.setAttributedString(attributedText ?? NSAttributedString())
      isRightToLeft = Self.isRightToLeft(attributedText?.string ?? "")
      accessibilityLabel = attributedText?.string
      isTextLayoutValid = false
      setNeedsDisplay()
    }
  }

  private let textStorage = NSTextStorage()
  private let layoutManager = NSLayoutManager()
  private let textContainer = NSTextContainer()
  private var textOrigin = CGPoint.zero
  private var textLayoutSize = CGSize.zero
  private var isTextLayoutValid = false
  private var isRightToLeft = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    isOpaque = false
    backgroundColor = .clear
    contentMode = .redraw
    isUserInteractionEnabled = false
    isAccessibilityElement = true
    accessibilityTraits = .staticText
    textContainer.lineFragmentPadding = 0
    textContainer.lineBreakMode = .byWordWrapping
    textContainer.maximumNumberOfLines = 5
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
  }

  override func draw(_ rect: CGRect) {
    updateTextLayoutIfNeeded()
    let glyphRange = layoutManager.glyphRange(for: textContainer)
    layoutManager.drawBackground(forGlyphRange: glyphRange, at: textOrigin)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
  }

  /// The area of the sung text: the text before the active cue and the sung part of the active cue.
  /// The excluded cue is left out, because it is drawn elsewhere.
  func sungPath(
    cueRanges: [NSRange],
    progress: LyricsCueProgress?,
    excludedCueIndex: Int? = nil
  )
    -> CGPath {
    updateTextLayoutIfNeeded()
    let path = CGMutablePath()
    guard let progress, let activeRange = cueRanges.object(at: progress.cueIndex) else {
      return path
    }
    var sungRanges = [NSRange(location: 0, length: activeRange.location)]
    if let excludedCueIndex, excludedCueIndex < progress.cueIndex,
       let excluded = cueRanges.object(at: excludedCueIndex) {
      sungRanges = [
        NSRange(location: 0, length: excluded.location),
        NSRange(
          location: NSMaxRange(excluded),
          length: max(activeRange.location - NSMaxRange(excluded), 0)
        ),
      ]
    }
    for range in sungRanges {
      for rect in enclosingRects(forCharacterRange: range) {
        path.addRect(rect)
      }
    }
    if excludedCueIndex != progress.cueIndex {
      path.addPath(partialPath(forCharacterRange: activeRange, fraction: progress.fraction))
    }
    return path
  }

  /// The area of the first part of the characters, in reading direction
  func partialPath(forCharacterRange characterRange: NSRange, fraction: Double) -> CGPath {
    let path = CGMutablePath()
    let rects = rects(forCharacterRange: characterRange)
    var sungWidth = rects.reduce(0) { $0 + $1.width } * fraction
    for rect in rects where sungWidth > 0 {
      let width = min(rect.width, sungWidth)
      let x = isRightToLeft ? rect.maxX - width : rect.minX
      path.addRect(CGRect(x: x, y: rect.minY, width: width, height: rect.height))
      sungWidth -= width
    }
    return path
  }

  /// One rect for each line fragment that the characters cover
  func rects(forCharacterRange characterRange: NSRange) -> [CGRect] {
    updateTextLayoutIfNeeded()
    return enclosingRects(forCharacterRange: characterRange)
  }

  private func updateTextLayoutIfNeeded() {
    if isTextLayoutValid, textLayoutSize == bounds.size { return }
    textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    // on a whole pixel, like UILabel, so that the glyphs stay sharp
    let scale = max(traitCollection.displayScale, 1)
    textOrigin = CGPoint(x: 0, y: ((bounds.height - usedRect.height) / 2 * scale).rounded() / scale)
    textLayoutSize = bounds.size
    isTextLayoutValid = true
  }

  private func enclosingRects(forCharacterRange characterRange: NSRange) -> [CGRect] {
    guard characterRange.length > 0 else { return [] }
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: characterRange,
      actualCharacterRange: nil
    )
    var rects = [CGRect]()
    layoutManager.enumerateEnclosingRects(
      forGlyphRange: glyphRange,
      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
      in: textContainer
    ) { rect, _ in
      rects.append(rect.offsetBy(dx: self.textOrigin.x, dy: self.textOrigin.y))
    }
    return rects
  }

  private static func isRightToLeft(_ text: String) -> Bool {
    guard !text.isEmpty,
          let language = CFStringTokenizerCopyBestStringLanguage(
            text as CFString,
            CFRange(location: 0, length: (text as NSString).length)
          ) as String?
    else { return false }
    return Locale.Language(identifier: language).characterDirection == .rightToLeft
  }
}
