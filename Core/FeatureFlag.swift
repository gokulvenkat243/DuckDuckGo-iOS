//
//  FeatureFlag.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

public enum FeatureFlag: String {
    case debugMenu
    case sync
    case autofillCredentialInjecting
    case autofillCredentialsSaving
    case autofillInlineIconCredentials
    case autofillAccessCredentialManagement
    case autofillPasswordGeneration
    case autofillOnByDefault
    case autofillFailureReporting
    case autofillOnForExistingUsers
    case autofillUnknownUsernameCategorization
    case incontextSignup
    case autoconsentOnByDefault
    case history
    case newTabPageSections
    case duckPlayer
    case duckPlayerOpenInNewTab
    case sslCertificatesBypass
    case syncPromotionBookmarks
    case syncPromotionPasswords
    case onboardingHighlights
    case onboardingAddToDock
    case autofillSurveys
    case autcompleteTabs
    case textZoom
    case adAttributionReporting

    /// https://app.asana.com/0/72649045549333/1208231259093710/f
    case networkProtectionUserTips

    /// https://app.asana.com/0/72649045549333/1208617860225199/f
    case networkProtectionEnforceRoutes
    
    /// https://app.asana.com/0/1208592102886666/1208613627589762/f
    case crashReportOptInStatusResetting
    case isPrivacyProLaunchedROW
    case isPrivacyProLaunchedROWOverride

    /// https://app.asana.com/0/0/1208767141940869/f
    case freeTrials
}

extension FeatureFlag: FeatureFlagDescribing {

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    public var supportsLocalOverriding: Bool {
        switch self {
        case .isPrivacyProLaunchedROWOverride:
            return true
        default:
            return false
        }
    }

    public var source: FeatureFlagSource {
        switch self {
        case .debugMenu:
            return .internalOnly()
        case .sync:
            return .remoteReleasable(.subfeature(SyncSubfeature.level0ShowSync))
        case .autofillCredentialInjecting:
            return .remoteReleasable(.subfeature(AutofillSubfeature.credentialsAutofill))
        case .autofillCredentialsSaving:
            return .remoteReleasable(.subfeature(AutofillSubfeature.credentialsSaving))
        case .autofillInlineIconCredentials:
            return .remoteReleasable(.subfeature(AutofillSubfeature.inlineIconCredentials))
        case .autofillAccessCredentialManagement:
            return .remoteReleasable(.subfeature(AutofillSubfeature.accessCredentialManagement))
        case .autofillPasswordGeneration:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordGeneration))
        case .autofillOnByDefault:
            return .remoteReleasable(.subfeature(AutofillSubfeature.onByDefault))
        case .autofillFailureReporting:
            return .remoteReleasable(.feature(.autofillBreakageReporter))
        case .autofillOnForExistingUsers:
            return .remoteReleasable(.subfeature(AutofillSubfeature.onForExistingUsers))
        case .autofillUnknownUsernameCategorization:
            return .remoteReleasable(.subfeature(AutofillSubfeature.unknownUsernameCategorization))
        case .incontextSignup:
            return .remoteReleasable(.feature(.incontextSignup))
        case .autoconsentOnByDefault:
            return .remoteReleasable(.subfeature(AutoconsentSubfeature.onByDefault))
        case .history:
            return .remoteReleasable(.feature(.history))
        case .newTabPageSections:
            return .remoteDevelopment(.feature(.newTabPageImprovements))
        case .duckPlayer:
            return .remoteReleasable(.subfeature(DuckPlayerSubfeature.enableDuckPlayer))
        case .duckPlayerOpenInNewTab:
            return .remoteReleasable(.subfeature(DuckPlayerSubfeature.openInNewTab))
        case .sslCertificatesBypass:
            return .remoteReleasable(.subfeature(SslCertificatesSubfeature.allowBypass))
        case .syncPromotionBookmarks:
            return .remoteReleasable(.subfeature(SyncPromotionSubfeature.bookmarks))
        case .syncPromotionPasswords:
            return .remoteReleasable(.subfeature(SyncPromotionSubfeature.passwords))
        case .onboardingHighlights:
            return .internalOnly()
        case .onboardingAddToDock:
            return .internalOnly()
        case .autofillSurveys:
            return .remoteReleasable(.feature(.autofillSurveys))
        case .autcompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .networkProtectionUserTips:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.userTips))
        case .textZoom:
            return .remoteReleasable(.feature(.textZoom))
        case .networkProtectionEnforceRoutes:
            return .remoteDevelopment(.subfeature(NetworkProtectionSubfeature.enforceRoutes))
        case .adAttributionReporting:
            return .remoteReleasable(.feature(.adAttributionReporting))
        case .crashReportOptInStatusResetting:
            return .internalOnly()
        case .isPrivacyProLaunchedROW:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.isLaunchedROW))
        case .isPrivacyProLaunchedROWOverride:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.isLaunchedROWOverride))
        case .freeTrials:
            return .remoteDevelopment(.subfeature(PrivacyProSubfeature.freeTrials))
        }
    }
}

extension FeatureFlagger {
    public func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        return isFeatureOn(for: featureFlag)
    }
}
