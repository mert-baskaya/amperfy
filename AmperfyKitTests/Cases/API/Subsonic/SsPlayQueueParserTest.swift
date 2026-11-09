//
//  SsPlayQueueParserTest.swift
//  AmperfyKitTests
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

@testable import AmperfyKit
import XCTest

// MARK: - SongId

// The samples are responses of Navidrome 0.64.2. In example 1 of both endpoints, the same queue
// has "Enjoy the Silence" at index 0 and 3, and index 3 is the current song.

private enum SongId {
  static let enjoyTheSilence = "3p3V5tsCsltVIhPGUP1N9a"
  static let itsNoGood = "4hqrVF0Lo9pM5iUG5OCSTB"
  static let strangelove = "3f3WnQLOUnHCo1E7VwGQUg"
  static let personalJesus = "61lntTfaWaQoIofKFdJPg3"
}

// MARK: - SsPlayQueueParserTest

class SsPlayQueueParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "playQueue_example_1")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsPlayQueueParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(),
      prefetch: prefetch,
      account: account,
      library: library
    )
  }

  override func checkCorrectParsing() {
    guard let parser = ssParserDelegate as? SsPlayQueueParserDelegate else { XCTFail(); return }
    prefetchIdTester.checkPrefetchIdCounts(
      artworkCount: 3,
      genreNameCount: 2,
      artistCount: 3,
      albumCount: 3,
      songCount: 3,
      artistFetchCount: 1 // the contributors are not created
    )

    XCTAssertEqual(
      parser.parsedSongs.map { $0.id },
      [SongId.enjoyTheSilence, SongId.itsNoGood, SongId.strangelove, SongId.enjoyTheSilence]
    )
    XCTAssertEqual(parser.parsedSongs[1].title, "It's No Good")
    XCTAssertEqual(parser.parsedSongs[1].album?.name, "Ultra")
    XCTAssertEqual(parser.parsedSongs[1].artist?.name, "Depeche Mode")
    XCTAssertEqual(parser.parsedSongs[1].duration, 358)
    // the id of the current song does not tell which of two equal songs is current
    XCTAssertEqual(parser.currentId, SongId.enjoyTheSilence)
    XCTAssertNil(parser.currentIndexAttribute)
    XCTAssertEqual(parser.currentIndex, 0)
    XCTAssertEqual(parser.positionMs, 12345)
    XCTAssertEqual(parser.changed, "2026-11-09T14:48:28.754830325Z")
    XCTAssertEqual(parser.changedBy, "amperfy-probe")
  }
}

// MARK: - SsPlayQueueByIndexExample1ParserTest

class SsPlayQueueByIndexExample1ParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "playQueueByIndex_example_1")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsPlayQueueParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(),
      prefetch: prefetch,
      account: account,
      library: library
    )
  }

  override func checkCorrectParsing() {
    guard let parser = ssParserDelegate as? SsPlayQueueParserDelegate else { XCTFail(); return }
    prefetchIdTester.checkPrefetchIdCounts(
      artworkCount: 3,
      genreNameCount: 2,
      artistCount: 3,
      albumCount: 3,
      songCount: 3,
      artistFetchCount: 1
    )

    XCTAssertEqual(
      parser.parsedSongs.map { $0.id },
      [SongId.enjoyTheSilence, SongId.itsNoGood, SongId.strangelove, SongId.enjoyTheSilence]
    )
    XCTAssertTrue(parser.parsedSongs[0] === parser.parsedSongs[3])
    XCTAssertNil(parser.currentId)
    XCTAssertEqual(parser.currentIndex, 3)
    XCTAssertEqual(parser.positionMs, 12345)
    XCTAssertEqual(parser.changed, "2026-11-09T14:48:28.754830325Z")
    XCTAssertEqual(parser.changedBy, "amperfy-probe")
  }
}

// MARK: - SsPlayQueueByIndexExample2ParserTest

/// A queue that Feishin saved, paused at the start of the current song
class SsPlayQueueByIndexExample2ParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "playQueueByIndex_example_2")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsPlayQueueParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(),
      prefetch: prefetch,
      account: account,
      library: library
    )
  }

  override func checkCorrectParsing() {
    guard let parser = ssParserDelegate as? SsPlayQueueParserDelegate else { XCTFail(); return }
    prefetchIdTester.checkPrefetchIdCounts(
      artworkCount: 4,
      genreNameCount: 2,
      artistCount: 3,
      albumCount: 3,
      songCount: 4,
      artistFetchCount: 1
    )

    XCTAssertEqual(
      parser.parsedSongs.map { $0.id },
      [SongId.enjoyTheSilence, SongId.itsNoGood, SongId.strangelove, SongId.personalJesus]
    )
    XCTAssertEqual(parser.currentIndex, 0)
    // Navidrome leaves out a position of 0
    XCTAssertEqual(parser.positionMs, 0)
    XCTAssertEqual(parser.changed, "2026-11-09T14:48:08.284026245Z")
    XCTAssertEqual(parser.changedBy, "Feishin")
  }
}

// MARK: - SsPlayQueueByIndexExample3ParserTest

/// No client saved a queue yet
class SsPlayQueueByIndexExample3ParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "playQueueByIndex_example_3")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsPlayQueueParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(),
      prefetch: prefetch,
      account: account,
      library: library
    )
  }

  override func checkCorrectParsing() {
    guard let parser = ssParserDelegate as? SsPlayQueueParserDelegate else { XCTFail(); return }
    prefetchIdTester.checkPrefetchIdCounts()
    XCTAssertTrue(parser.parsedSongs.isEmpty)
    XCTAssertEqual(parser.currentIndex, 0)
    XCTAssertEqual(parser.changed, "0001-01-01T00:00:00Z")
    XCTAssertEqual(parser.changedBy, "")
  }
}

// MARK: - PlayQueueFormPostTest

class PlayQueueFormPostTest: XCTestCase {
  func testFormPostRequest_KeepsOrderOfQueue() throws {
    let url = try XCTUnwrap(URL(
      string: "https://music.example.org/rest/savePlayQueueByIndex.view?u=user&t=token&s=salt&v=1.13.0&c=Amperfy&id=c3&id=a1&id=b2&id=a1&currentIndex=3&position=12345"
    ))
    let request = try SubsonicServerApi.createFormPostRequest(url: url, headers: nil)

    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://music.example.org/rest/savePlayQueueByIndex.view"
    )
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    let pairs = body.split(separator: "&").map { String($0) }
    XCTAssertEqual(pairs.filter { $0.hasPrefix("id=") }, ["id=c3", "id=a1", "id=b2", "id=a1"])
    XCTAssertTrue(pairs.contains("currentIndex=3"))
    XCTAssertTrue(pairs.contains("position=12345"))
    XCTAssertTrue(pairs.contains("u=user"))
    XCTAssertTrue(pairs.contains("c=Amperfy"))
  }
}
