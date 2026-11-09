//
//  SsPlayQueueParserDelegate.swift
//  AmperfyKit
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

import Foundation

/// Parses `getPlayQueue` (element `playQueue`) and `getPlayQueueByIndex` (element `playQueueByIndex`)
class SsPlayQueueParserDelegate: SsSongParserDelegate {
  private(set) var currentId: String?
  private(set) var currentIndexAttribute: Int?
  private(set) var positionMs = 0
  private(set) var changed = ""
  private(set) var changedBy = ""

  /// The index of the current song in `parsedSongs`. `currentIndex` wins over `current`, because
  /// `current` is ambiguous when the queue has the same song more than once.
  var currentIndex: Int {
    if let currentIndexAttribute, parsedSongs.indices.contains(currentIndexAttribute) {
      return currentIndexAttribute
    }
    if let currentId, let index = parsedSongs.firstIndex(where: { $0.id == currentId }) {
      return index
    }
    return 0
  }

  override func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    if elementName == "playQueue" || elementName == "playQueueByIndex" {
      currentId = attributeDict["current"]
      currentIndexAttribute = attributeDict["currentIndex"].flatMap { Int($0) }
      positionMs = attributeDict["position"].flatMap { Int($0) } ?? 0
      changed = attributeDict["changed"] ?? ""
      changedBy = attributeDict["changedBy"] ?? ""
    }

    super.parser(
      parser,
      didStartElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName,
      attributes: attributeDict
    )
  }
}
