//
//  WebCacheManagerTests.swift
//  UnitTests
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import TestUtils

extension HTTPCookie {

    static func make(name: String = "name",
                     value: String = "value",
                     domain: String = "example.com",
                     path: String = "/",
                     policy: HTTPCookieStringPolicy? = nil) -> HTTPCookie {

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]

        if policy != nil {
            properties[HTTPCookiePropertyKey.sameSitePolicy] = policy
        }

        return HTTPCookie(properties: properties)!    }

}

class WebCacheManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CookieStorage().cookies = []
        CookieStorage().isConsumed = true

        if #available(iOS 17, *) {
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { uuids in
                uuids.forEach {
                    WKWebsiteDataStore.remove(forIdentifier: $0, completionHandler: { _ in })
                }
            }
        }
    }

    @available(iOS 17, *)
    @MainActor
    func testEnsureIdAllocatedAfterClearing() async throws {
        let fireproofing = MockFireproofing(domains: [])

        let storage = CookieStorage()

        let inMemoryDataStoreIdManager = DataStoreIdManager(store: MockKeyValueStore())
        XCTAssertNil(inMemoryDataStoreIdManager.currentId)

        await WebCacheManager.shared.clear(cookieStorage: storage, fireproofing: fireproofing, dataStoreIdManager: inMemoryDataStoreIdManager)

        XCTAssertNotNil(inMemoryDataStoreIdManager.currentId)
        let oldId = inMemoryDataStoreIdManager.currentId?.uuidString
        XCTAssertNotNil(oldId)

        await WebCacheManager.shared.clear(cookieStorage: storage, fireproofing: fireproofing, dataStoreIdManager: inMemoryDataStoreIdManager)

        XCTAssertNotNil(inMemoryDataStoreIdManager.currentId)
        XCTAssertNotEqual(inMemoryDataStoreIdManager.currentId?.uuidString, oldId)
    }

    @available(iOS 17, *)
    @MainActor
    func testWhenCookiesHaveSubDomainsOnSubDomainsAndWidlcardsThenOnlyMatchingCookiesRetained() async throws {
        let fireproofing = MockFireproofing(domains: ["mobile.twitter.com"])

        let defaultStore = WKWebsiteDataStore.default()
        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        let initialCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(0, initialCount)

        await defaultStore.httpCookieStore.setCookie(.make(domain: "twitter.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: ".twitter.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: "mobile.twitter.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: "fake.mobile.twitter.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: ".fake.mobile.twitter.com"))

        let loadedCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(5, loadedCount)

        let cookieStore = CookieStorage()
        await WebCacheManager.shared.clear(cookieStorage: cookieStore, fireproofing: fireproofing, dataStoreIdManager: DataStoreIdManager(store: MockKeyValueStore()))

        let cookies = await defaultStore.httpCookieStore.allCookies()
        XCTAssertEqual(cookies.count, 0)

        XCTAssertEqual(2, cookieStore.cookies.count)
        XCTAssertTrue(cookieStore.cookies.contains(where: { $0.domain == ".twitter.com" }))
        XCTAssertTrue(cookieStore.cookies.contains(where: { $0.domain == "mobile.twitter.com" }))
    }
    
    @MainActor
    func testWhenRemovingCookieForDomainThenItIsRemovedFromCookieStorage() async {
        let defaultStore = WKWebsiteDataStore.default()
        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        let initialCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(0, initialCount)

        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await defaultStore.httpCookieStore.setCookie(.make(domain: "www.example.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: ".example.com"))
        let cookies = await defaultStore.httpCookieStore.allCookies()
        XCTAssertEqual(cookies.count, 2)

        await WebCacheManager.shared.removeCookies(forDomains: ["www.example.com"], dataStore: WKWebsiteDataStore.default())
        let cleanCookies = await defaultStore.httpCookieStore.allCookies()
        XCTAssertEqual(cleanCookies.count, 0)
    }

    @MainActor
    func testWhenClearedThenCookiesWithParentDomainsAreRetained() async {
        let fireproofing = MockFireproofing(domains: ["www.example.com"])

        let defaultStore = WKWebsiteDataStore.default()
        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        let initialCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(0, initialCount)

        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await defaultStore.httpCookieStore.setCookie(.make(domain: "example.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: ".example.com"))

        let cookieStorage = CookieStorage()
        
        await WebCacheManager.shared.clear(cookieStorage: cookieStorage,
                                           fireproofing: fireproofing,
                                           dataStoreIdManager: DataStoreIdManager(store: MockKeyValueStore()))
        let cookies = await defaultStore.httpCookieStore.allCookies()

        XCTAssertEqual(cookies.count, 0)
        XCTAssertEqual(cookieStorage.cookies.count, 1)
        XCTAssertEqual(cookieStorage.cookies[0].domain, ".example.com")
    }

    @MainActor
    @available(iOS 17, *)
    func testWhenClearedWithDataStoreContainerThenDDGCookiesAreRetained() async throws {
        throw XCTSkip("WKWebsiteDataStore(forIdentifier:) does not persist cookies properly until attached to a running webview")
        
        // This test should look like `testWhenClearedWithLegacyContainerThenDDGCookiesAreRetained` but
        //  with a container ID set on the `dataStoreIdManager`.
    }

    @MainActor
    func testWhenClearedWithLegacyContainerThenDDGCookiesAreRetained() async {
        let fireproofing = MockFireproofing(domains: ["www.example.com"])

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        await cookieStore.setCookie(.make(name: "name", value: "value", domain: "duckduckgo.com"))
        await cookieStore.setCookie(.make(name: "name", value: "value", domain: "subdomain.duckduckgo.com"))

        let storage = CookieStorage()
        storage.isConsumed = true
        
        await WebCacheManager.shared.clear(cookieStorage: storage, fireproofing: fireproofing, dataStoreIdManager: DataStoreIdManager(store: MockKeyValueStore()))

        XCTAssertEqual(storage.cookies.count, 2)
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "duckduckgo.com" }))
        XCTAssertTrue(storage.cookies.contains(where: { $0.domain == "subdomain.duckduckgo.com" }))
    }
    
    @MainActor
    func testWhenClearedThenCookiesForLoginsAreRetained() async {
        let fireproofing = MockFireproofing(domains: ["www.example.com"])

        let defaultStore = WKWebsiteDataStore.default()
        await defaultStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        let initialCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(0, initialCount)

        await defaultStore.httpCookieStore.setCookie(.make(domain: "www.example.com"))
        await defaultStore.httpCookieStore.setCookie(.make(domain: "facebook.com"))

        let loadedCount = await defaultStore.httpCookieStore.allCookies().count
        XCTAssertEqual(2, loadedCount)

        let cookieStore = CookieStorage()
        
        await WebCacheManager.shared.clear(cookieStorage: cookieStore, fireproofing: fireproofing, dataStoreIdManager: DataStoreIdManager(store: MockKeyValueStore()))

        let cookies = await defaultStore.httpCookieStore.allCookies()
        XCTAssertEqual(cookies.count, 0)
        
        XCTAssertEqual(1, cookieStore.cookies.count)
        XCTAssertEqual(cookieStore.cookies[0].domain, "www.example.com")
    }

    @MainActor
    func x_testWhenAccessingObservationsDbThenValidDatabasePoolIsReturned() {
        let pool = WebCacheManager.shared.getValidDatabasePool()
        XCTAssertNotNil(pool, "DatabasePool should not be nil")
    }

    // MARK: Mocks
    
    class MockFireproofing: UserDefaultsFireproofing {
        override var allowedDomains: [String] {
            return domains
        }

        let domains: [String]
        init(domains: [String]) {
            self.domains = domains
        }
    }
    
}
