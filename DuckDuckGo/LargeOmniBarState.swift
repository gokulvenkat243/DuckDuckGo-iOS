//
//  LargeOmniBarState.swift
//  DuckDuckGo
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
import Core

struct LargeOmniBarState {
    
    struct HomeEmptyEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = false
        let clearTextOnStart = true
        let allowsTrackersAnimation = false
        let showPrivacyIcon = false
        let showBackground = false
        let showClear = false
        let showAbort = false
        let showRefresh = false
        let showMenu = false
        let showSettings = true
        let showCancel: Bool = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEditingStartedState: OmniBarState { return self }
        var onTextClearedState: OmniBarState { return self }
        var onTextEnteredState: OmniBarState { return HomeTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStartedState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStoppedState: OmniBarState { return self }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var showSearchLoupe: Bool { !voiceSearchHelper.isVoiceSearchEnabled }
        var showVoiceSearch: Bool { voiceSearchHelper.isVoiceSearchEnabled }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool

        func withLoading() -> LargeOmniBarState.HomeEmptyEditingState {
            Self.init(voiceSearchHelper: voiceSearchHelper, isLoading: true)
        }

        func withoutLoading() -> LargeOmniBarState.HomeEmptyEditingState {
            Self.init(voiceSearchHelper: voiceSearchHelper, isLoading: false)
        }
    }

    struct HomeTextEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = false
        let clearTextOnStart = false
        let allowsTrackersAnimation = false
        let showPrivacyIcon = false
        let showBackground = false
        let showClear = true
        let showAbort = false
        let showRefresh = false
        let showMenu = false
        let showSettings = true
        let showCancel: Bool = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEditingStartedState: OmniBarState { return self }
        var onTextClearedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextEnteredState: OmniBarState { return self }
        var onBrowsingStartedState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStoppedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.HomeTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return HomeTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var showSearchLoupe: Bool { !voiceSearchHelper.isVoiceSearchEnabled }
        var showVoiceSearch: Bool { voiceSearchHelper.isVoiceSearchEnabled }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool
    }

    struct HomeNonEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = false
        let clearTextOnStart = true
        let allowsTrackersAnimation = false
        let showSearchLoupe = true
        let showPrivacyIcon = false
        let showBackground = true
        let showClear = false
        let showAbort = false
        let showRefresh = false
        let showMenu = false
        let showSettings = true
        let showCancel: Bool = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return self }
        var onEditingStartedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextClearedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextEnteredState: OmniBarState { return HomeTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStartedState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStoppedState: OmniBarState { return HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var showVoiceSearch: Bool { voiceSearchHelper.isVoiceSearchEnabled }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool
    }

    struct BrowsingEmptyEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = true
        let clearTextOnStart = true
        let allowsTrackersAnimation = false
        let showPrivacyIcon = false
        let showBackground = false
        let showClear = false
        let showAbort = false
        let showRefresh = false
        let showMenu = true
        let showSettings = false
        let showCancel: Bool = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEditingStartedState: OmniBarState { return self }
        var onTextClearedState: OmniBarState { return self }
        var onTextEnteredState: OmniBarState { return BrowsingTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStartedState: OmniBarState { return self }
        var onBrowsingStoppedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.BrowsingEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return BrowsingEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var showSearchLoupe: Bool { !voiceSearchHelper.isVoiceSearchEnabled }
        var showVoiceSearch: Bool { voiceSearchHelper.isVoiceSearchEnabled }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool
    }

    struct BrowsingTextEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = true
        let clearTextOnStart = false
        let allowsTrackersAnimation = false
        let showPrivacyIcon = false
        let showBackground = false
        let showClear = true
        let showAbort = false
        let showRefresh = false
        let showMenu = true
        let showSettings = false
        let showCancel: Bool = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEditingStartedState: OmniBarState { return self }
        var onTextClearedState: OmniBarState { return BrowsingEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextEnteredState: OmniBarState { return self }
        var onBrowsingStartedState: OmniBarState { return self }
        var onBrowsingStoppedState: OmniBarState { return HomeEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.BrowsingTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return BrowsingTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var showSearchLoupe: Bool { !voiceSearchHelper.isVoiceSearchEnabled }
        var showVoiceSearch: Bool { voiceSearchHelper.isVoiceSearchEnabled }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool
    }

    struct BrowsingNonEditingState: OmniBarState, OmniBarLoadingBearerStateCreating {
        let hasLargeWidth: Bool = true
        let showBackButton: Bool = true
        let showForwardButton: Bool = true
        let showBookmarksButton: Bool = true
        let showShareButton: Bool = true
        let clearTextOnStart = false
        let allowsTrackersAnimation = true
        let showSearchLoupe = false
        let showPrivacyIcon = true
        let showBackground = true
        let showClear = false
        var showAbort: Bool { isLoading }
        var showRefresh: Bool { !isLoading }
        let showMenu = true
        let showSettings = false
        let showCancel: Bool = false
        let showVoiceSearch = false
        var name: String { return "Pad" + Type.name(self) }
        var onEditingStoppedState: OmniBarState { return self }
        var onEditingStartedState: OmniBarState { return BrowsingTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextClearedState: OmniBarState { return BrowsingEmptyEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onTextEnteredState: OmniBarState { return BrowsingTextEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onBrowsingStartedState: OmniBarState { return self }
        var onBrowsingStoppedState: OmniBarState { return HomeNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onEnterPadState: OmniBarState { return self }
        var onEnterPhoneState: OmniBarState { return SmallOmniBarState.BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }
        var onReloadState: OmniBarState { return BrowsingNonEditingState(voiceSearchHelper: voiceSearchHelper, isLoading: isLoading) }

        let voiceSearchHelper: VoiceSearchHelperProtocol
        let isLoading: Bool
    }

}
