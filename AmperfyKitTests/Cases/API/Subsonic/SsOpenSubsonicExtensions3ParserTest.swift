//
//  SsOpenSubsonicExtensions3ParserTest.swift
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

/// Navidrome 0.64.2 lists the extensions that the play queue sync uses
class SsOpenSubsonicExtensions3ParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "OpenSubsonicExtensions_example_3")
  }

  override func createParserDelegate() {
    ssParserDelegate =
      SsOpenSubsonicExtensionsParserDelegate(performanceMonitor: MOCK_PerformanceMonitor())
  }

  override func checkCorrectParsing() {
    guard let extensionsParser = ssParserDelegate as? SsOpenSubsonicExtensionsParserDelegate
    else {
      XCTFail()
      return
    }
    prefetchIdTester.checkPrefetchIdCounts()

    let response = extensionsParser.openSubsonicExtensionsResponse
    XCTAssertEqual(response.serverVersion, "0.64.2 (10114574)")
    XCTAssertTrue(
      response.supportedExtensions.contains(OpenSubsonicExtension.indexBasedQueue.rawValue)
    )
    XCTAssertTrue(response.supportedExtensions.contains(OpenSubsonicExtension.formPost.rawValue))
  }
}
