//
//  Fireproofing.swift
//  Core
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

import Foundation

public protocol Fireproofing {

    var loginDetectionEnabled: Bool { get set }
    var allowedDomains: [String] { get }

    func isAllowed(cookieDomain: String) -> Bool
    func isAllowed(fireproofDomain domain: String) -> Bool
    func addToAllowed(domain: String)
    func remove(domain: String)
    func clearAll()

}

// This class is not final because we override allowed domains in WebCacheManagerTests
public class UserDefaultsFireproofing: Fireproofing {

    public static let shared: Fireproofing = UserDefaultsFireproofing()

    public struct Notifications {
        public static let loginDetectionStateChanged = Foundation.Notification.Name("com.duckduckgo.ios.PreserveLogins.loginDetectionStateChanged")
    }

    @UserDefaultsWrapper(key: .fireproofingAllowedDomains, defaultValue: [])
    private(set) public var allowedDomains: [String]

    @UserDefaultsWrapper(key: .fireproofingDetectionEnabled, defaultValue: false)
    public var loginDetectionEnabled: Bool {
        didSet {
            NotificationCenter.default.post(name: Notifications.loginDetectionStateChanged, object: nil)
        }
    }

    public func addToAllowed(domain: String) {
        allowedDomains += [domain]
    }

    public func isAllowed(cookieDomain: String) -> Bool {

        return allowedDomains.contains(where: { $0 == cookieDomain
            || ".\($0)" == cookieDomain
            || (cookieDomain.hasPrefix(".") && $0.hasSuffix(cookieDomain)) })
    }

    public func remove(domain: String) {
        allowedDomains = allowedDomains.filter { $0 != domain }
    }

    public func clearAll() {
        allowedDomains = []
    }

    public func isAllowed(fireproofDomain domain: String) -> Bool {
        return allowedDomains.contains(domain)
    }

}
