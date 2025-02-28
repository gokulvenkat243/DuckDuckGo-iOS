//
//  CookieStorageTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import Core
import WebKit

public class CookieStorageTests: XCTestCase {
    
    var storage: CookieStorage!
    
    // This is updated by the `make` function which preserves any cookies added as part of this test
    let fireproofing = UserDefaultsFireproofing.shared

    static let userDefaultsSuiteName = "test"
    
    public override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: Self.userDefaultsSuiteName)!
        defaults.removePersistentDomain(forName: Self.userDefaultsSuiteName)
        storage = CookieStorage(userDefaults: defaults)
        storage.isConsumed = true
        fireproofing.clearAll()
    }
    
    func testWhenDomainRemovesAllCookesThenTheyAreClearedFromPersisted() {
        fireproofing.addToAllowed(domain: "example.com")
        
        XCTAssertEqual(storage.updateCookies([
            make("example.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing), .empty)

        XCTAssertEqual(1, storage.cookies.count)
        
        storage.isConsumed = true
        storage.updateCookies([], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(0, storage.cookies.count)

    }

    func testWhenUpdatedThenDuckDuckGoCookiesAreNotRemoved() {
        storage.updateCookies([
            make("duckduckgo.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(1, storage.cookies.count)

        storage.isConsumed = true
        storage.updateCookies([
            make("duckduckgo.com", name: "x", value: "1"),
            make("test.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(2, storage.cookies.count)

        storage.isConsumed = true
        storage.updateCookies([
            make("usedev1.duckduckgo.com", name: "x", value: "1"),
            make("duckduckgo.com", name: "x", value: "1"),
            make("test.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(3, storage.cookies.count)

    }
    
    func testWhenUpdatedThenCookiesWithFutureExpirationAreNotRemoved() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1", expires: .distantFuture),
            make("example.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(2, storage.cookies.count)
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "test.com" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "example.com" }))

    }
    
    func testWhenUpdatingThenExistingExpiredCookiesAreRemoved() {
        storage.cookies = [
            make("test.com", name: "x", value: "1", expires: Date(timeIntervalSinceNow: -100)),
        ]
        XCTAssertEqual(1, storage.cookies.count)

        storage.isConsumed = true
        storage.updateCookies([
            make("example.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(1, storage.cookies.count)
        XCTAssertFalse(storage.cookies.contains(where: { $0.domain == "test.com" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "example.com" }))

    }
    
    func testWhenExpiredCookieIsAddedThenItIsNotPersisted() {

        storage.updateCookies([
            make("example.com", name: "x", value: "1", expires: Date(timeIntervalSinceNow: -100)),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(0, storage.cookies.count)

    }
    
    func testWhenUpdatedThenNoLongerFireproofedDomainsAreCleared() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1"),
            make("example.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)

        fireproofing.remove(domain: "test.com")
        
        storage.isConsumed = true
        storage.updateCookies([
            make("example.com", name: "x", value: "1"),
        ], preservingFireproofedDomains: fireproofing)
        
        XCTAssertEqual(1, storage.cookies.count)
        XCTAssertFalse(storage.cookies.contains(where: { $0.domain == "test.com" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "example.com" }))
    }
    
    func testWhenStorageInitialiedThenItIsEmptyAndIsReadyToBeUpdated() {
        XCTAssertEqual(0, storage.cookies.count)
        XCTAssertTrue(storage.isConsumed)
    }
    
    func testWhenStorageIsUpdatedThenConsumedIsResetToFalse() {
        storage.isConsumed = true
        XCTAssertTrue(storage.isConsumed)
        storage.updateCookies([
            make("test.com", name: "x", value: "1")
        ], preservingFireproofedDomains: fireproofing)
        XCTAssertFalse(storage.isConsumed)
    }
    
    func testWhenStorageIsReinstanciatedThenUsesStoredData() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1")
        ], preservingFireproofedDomains: fireproofing)
        storage.isConsumed = true

        let otherStorage = CookieStorage(userDefaults: UserDefaults(suiteName: Self.userDefaultsSuiteName)!)
        XCTAssertEqual(1, otherStorage.cookies.count)
        XCTAssertTrue(otherStorage.isConsumed)
    }
     
    func testWhenStorageIsUpdatedThenUpdatingAddsNewCookies() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1")
        ], preservingFireproofedDomains: fireproofing)
        XCTAssertEqual(1, storage.cookies.count)
    }

    func testWhenStorageHasMatchingDOmainThenUpdatingReplacesCookies() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1")
        ], preservingFireproofedDomains: fireproofing)

        storage.isConsumed = true
        storage.updateCookies([
            make("test.com", name: "x", value: "2"),
            make("test.com", name: "y", value: "3"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(2, storage.cookies.count)
        XCTAssertFalse(storage.cookies.contains(where: { $0.domain == "test.com" && $0.name == "x" && $0.value == "1" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "test.com" && $0.name == "x" && $0.value == "2" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "test.com" && $0.name == "y" && $0.value == "3" }))
    }
    
    func testWhenStorageUpdatedAndNotConsumedThenNothingHappens() {
        storage.updateCookies([
            make("test.com", name: "x", value: "1")
        ], preservingFireproofedDomains: fireproofing)

        storage.updateCookies([
            make("example.com", name: "y", value: "3"),
        ], preservingFireproofedDomains: fireproofing)

        XCTAssertEqual(1, storage.cookies.count)
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "test.com" && $0.name == "x" && $0.value == "1" }))
    }
    
    func make(_ domain: String, name: String, value: String, expires: Date? = nil) -> HTTPCookie {
        fireproofing.addToAllowed(domain: domain)
        return HTTPCookie(properties: [
            .domain: domain,
            .name: name,
            .value: value,
            .path: "/",
            .expires: expires as Any
        ])!
    }
    
}
