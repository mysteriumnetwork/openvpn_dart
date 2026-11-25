import NetworkExtension
import XCTest


@testable import openvpn_dart

// Unit tests of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  // A tunnel that is re-establishing its link has not ended, and must not be
  // reported as though it had: it comes back by itself.
  func testReconnectingTunnelIsReportedAsConnecting() {
    XCTAssertEqual(statusName(for: .reasserting), "connecting")
  }

  func testMissingConfigurationIsReportedAsDisconnected() {
    XCTAssertEqual(statusName(for: .invalid), "disconnected")
  }

  func testEveryOtherStatusKeepsItsOwnName() {
    XCTAssertEqual(statusName(for: .connecting), "connecting")
    XCTAssertEqual(statusName(for: .connected), "connected")
    XCTAssertEqual(statusName(for: .disconnecting), "disconnecting")
    XCTAssertEqual(statusName(for: .disconnected), "disconnected")
  }

}
