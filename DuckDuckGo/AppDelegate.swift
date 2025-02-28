//
//  AppDelegate.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import UIKit
import Combine
import Common
import Core
import UserNotifications
import Kingfisher
import WidgetKit
import BackgroundTasks
import BrowserServicesKit
import Bookmarks
import Persistence
import Crashes
import Configuration
import Networking
import DDGSync
import RemoteMessaging
import SyncDataProviders
import Subscription
import NetworkProtection
import WebKit
import os.log

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate {
    
    private static let ShowKeyboardOnLaunchThreshold = TimeInterval(20)
    private struct ShortcutKey {
        static let clipboard = "com.duckduckgo.mobile.ios.clipboard"
        static let passwords = "com.duckduckgo.mobile.ios.passwords"
        static let openVPNSettings = "com.duckduckgo.mobile.ios.vpn.open-settings"
    }

    private var testing = false
    var appIsLaunching = false
    var overlayWindow: UIWindow?
    var window: UIWindow?

    private lazy var privacyStore = PrivacyUserDefaults()
    private var bookmarksDatabase: CoreDataDatabase = BookmarksDatabase.make()

    private let widgetRefreshModel = NetworkProtectionWidgetRefreshModel()
    private let tunnelDefaults = UserDefaults.networkProtectionGroupDefaults

    @MainActor
    private lazy var vpnWorkaround: VPNRedditSessionWorkaround = {
        return VPNRedditSessionWorkaround(
            accountManager: AppDependencyProvider.shared.accountManager,
            tunnelController: AppDependencyProvider.shared.networkProtectionTunnelController
        )
    }()

    private var autoClear: AutoClear?
    private var showKeyboardIfSettingOn = true
    private var lastBackgroundDate: Date?

    private(set) var homePageConfiguration: HomePageConfiguration!

    private(set) var remoteMessagingClient: RemoteMessagingClient!

    private(set) var syncService: DDGSync!
    private(set) var syncDataProviders: SyncDataProviders!
    private var syncDidFinishCancellable: AnyCancellable?
    private var syncStateCancellable: AnyCancellable?
    private var isSyncInProgressCancellable: AnyCancellable?

    private let crashCollection = CrashCollection(platform: .iOS)
    private var crashReportUploaderOnboarding: CrashCollectionOnboarding?

    private var autofillPixelReporter: AutofillPixelReporter?
    private var autofillUsageMonitor = AutofillUsageMonitor()

    private(set) var subscriptionFeatureAvailability: SubscriptionFeatureAvailability!
    private var subscriptionCookieManager: SubscriptionCookieManaging!
    private var subscriptionCookieManagerFeatureFlagCancellable: AnyCancellable?
    var privacyProDataReporter: PrivacyProDataReporting!

    // MARK: - Feature specific app event handlers

    private let tipKitAppEventsHandler = TipKitAppEventHandler()

    // MARK: lifecycle

    @UserDefaultsWrapper(key: .privacyConfigCustomURL, defaultValue: nil)
    private var privacyConfigCustomURL: String?

    var accountManager: AccountManager {
        AppDependencyProvider.shared.accountManager
    }

    @UserDefaultsWrapper(key: .didCrashDuringCrashHandlersSetUp, defaultValue: false)
    private var didCrashDuringCrashHandlersSetUp: Bool

    private let launchOptionsHandler = LaunchOptionsHandler()
    private let onboardingPixelReporter = OnboardingPixelReporter()

    private let voiceSearchHelper = VoiceSearchHelper()

    private let marketplaceAdPostbackManager = MarketplaceAdPostbackManager()

    private var didFinishLaunchingStartTime: CFAbsoluteTime?

    override init() {
        super.init()

        if !didCrashDuringCrashHandlersSetUp {
            didCrashDuringCrashHandlersSetUp = true
            CrashLogMessageExtractor.setUp(swapCxaThrow: false)
            didCrashDuringCrashHandlersSetUp = false
        }
    }

    // swiftlint:disable:next function_body_length
    // swiftlint:disable:next cyclomatic_complexity
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        didFinishLaunchingStartTime = CFAbsoluteTimeGetCurrent()
        defer {
            if let didFinishLaunchingStartTime {
                let launchTime = CFAbsoluteTimeGetCurrent() - didFinishLaunchingStartTime
                Pixel.fire(pixel: .appDidFinishLaunchingTime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                           withAdditionalParameters: [PixelParameters.time: String(launchTime)])
            }
        }


#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["UITESTING"] == "true" {
            // Disable hardware keyboards.
            let setHardwareLayout = NSSelectorFromString("setHardwareLayout:")
            UITextInputMode.activeInputModes
            // Filter `UIKeyboardInputMode`s.
                .filter({ $0.responds(to: setHardwareLayout) })
                .forEach { $0.perform(setHardwareLayout, with: nil) }
        }
#endif

#if DEBUG
        Pixel.isDryRun = true
#else
        Pixel.isDryRun = false
#endif

        ContentBlocking.shared.onCriticalError = presentPreemptiveCrashAlert
        // Explicitly prepare ContentBlockingUpdating instance before Tabs are created
        _ = ContentBlockingUpdating.shared

        // Can be removed after a couple of versions
        cleanUpMacPromoExperiment2()
        cleanUpIncrementalRolloutPixelTest()

        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)

        if isDebugBuild, let privacyConfigCustomURL, let url = URL(string: privacyConfigCustomURL) {
            Configuration.setURLProvider(CustomConfigurationURLProvider(customPrivacyConfigurationURL: url))
        } else {
            Configuration.setURLProvider(AppConfigurationURLProvider())
        }

        crashCollection.startAttachingCrashLogMessages { pixelParameters, payloads, sendReport in
            pixelParameters.forEach { params in
                Pixel.fire(pixel: .dbCrashDetected, withAdditionalParameters: params, includedParameters: [])
            }

            // Async dispatch because rootViewController may otherwise be nil here
            DispatchQueue.main.async {
                guard let viewController = self.window?.rootViewController else { return }

                let crashReportUploaderOnboarding = CrashCollectionOnboarding(appSettings: AppDependencyProvider.shared.appSettings)
                crashReportUploaderOnboarding.presentOnboardingIfNeeded(for: payloads, from: viewController, sendReport: sendReport)
                self.crashReportUploaderOnboarding = crashReportUploaderOnboarding
            }
        }

        clearTmp()

        _ = DefaultUserAgentManager.shared
        testing = ProcessInfo().arguments.contains("testing")
        if testing {
            Pixel.isDryRun = true
            _ = DefaultUserAgentManager.shared
            Database.shared.loadStore { _, _ in }
            _ = BookmarksDatabaseSetup().loadStoreAndMigrate(bookmarksDatabase: bookmarksDatabase)

            window = UIWindow(frame: UIScreen.main.bounds)
            window?.rootViewController = UIStoryboard.init(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()

            let blockingDelegate = BlockingNavigationDelegate()
            let webView = blockingDelegate.prepareWebView()
            window?.rootViewController?.view.addSubview(webView)
            window?.rootViewController?.view.backgroundColor = .red
            webView.frame = CGRect(x: 10, y: 10, width: 300, height: 300)

            let request = URLRequest(url: URL(string: "about:blank")!)
            webView.load(request)

            return true
        }

        removeEmailWaitlistState()

        var shouldPresentInsufficientDiskSpaceAlertAndCrash = false
        Database.shared.loadStore { context, error in
            guard let context = context else {
                
                let parameters = [PixelParameters.applicationState: "\(application.applicationState.rawValue)",
                                  PixelParameters.dataAvailability: "\(application.isProtectedDataAvailable)"]

                switch error {
                case .none:
                    fatalError("Could not create database stack: Unknown Error")
                case .some(CoreDataDatabase.Error.containerLocationCouldNotBePrepared(let underlyingError)):
                    Pixel.fire(pixel: .dbContainerInitializationError,
                               error: underlyingError,
                               withAdditionalParameters: parameters)
                    Thread.sleep(forTimeInterval: 1)
                    fatalError("Could not create database stack: \(underlyingError.localizedDescription)")
                case .some(let error):
                    Pixel.fire(pixel: .dbInitializationError,
                               error: error,
                               withAdditionalParameters: parameters)
                    if error.isDiskFull {
                        shouldPresentInsufficientDiskSpaceAlertAndCrash = true
                        return
                    } else {
                        Thread.sleep(forTimeInterval: 1)
                        fatalError("Could not create database stack: \(error.localizedDescription)")
                    }
                }
            }
            DatabaseMigration.migrate(to: context)
        }

        switch BookmarksDatabaseSetup().loadStoreAndMigrate(bookmarksDatabase: bookmarksDatabase) {
        case .success:
            break
        case .failure(let error):
            Pixel.fire(pixel: .bookmarksCouldNotLoadDatabase,
                       error: error)
            if error.isDiskFull {
                shouldPresentInsufficientDiskSpaceAlertAndCrash = true
            } else {
                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not create database stack: \(error.localizedDescription)")
            }
        }

        WidgetCenter.shared.reloadAllTimelines()

        Favicons.shared.migrateFavicons(to: Favicons.Constants.maxFaviconSize) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        PrivacyFeatures.httpsUpgrade.loadDataAsync()
        
        let variantManager = DefaultVariantManager()
        let daxDialogs = DaxDialogs.shared

        // assign it here, because "did become active" is already too late and "viewWillAppear"
        // has already been called on the HomeViewController so won't show the home row CTA
        cleanUpATBAndAssignVariant(variantManager: variantManager, daxDialogs: daxDialogs)

        // MARK: Sync initialisation
#if DEBUG
        let defaultEnvironment = ServerEnvironment.development
#else
        let defaultEnvironment = ServerEnvironment.production
#endif

        let environment = ServerEnvironment(
            UserDefaultsWrapper(
                key: .syncEnvironment,
                defaultValue: defaultEnvironment.description
            ).wrappedValue
        ) ?? defaultEnvironment

        let syncErrorHandler = SyncErrorHandler()

        syncDataProviders = SyncDataProviders(
            bookmarksDatabase: bookmarksDatabase,
            secureVaultErrorReporter: SecureVaultReporter(),
            settingHandlers: [FavoritesDisplayModeSyncHandler()],
            favoritesDisplayModeStorage: FavoritesDisplayModeStorage(),
            syncErrorHandler: syncErrorHandler,
            faviconStoring: Favicons.shared
        )

        let syncService = DDGSync(
            dataProvidersSource: syncDataProviders,
            errorEvents: SyncErrorHandler(),
            privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
            environment: environment
        )
        syncService.initializeIfNeeded()
        self.syncService = syncService

        privacyProDataReporter = PrivacyProDataReporter()

        isSyncInProgressCancellable = syncService.isSyncInProgressPublisher
            .filter { $0 }
            .sink { [weak syncService] _ in
                DailyPixel.fire(pixel: .syncDaily, includedParameters: [.appVersion])
                syncService?.syncDailyStats.sendStatsIfNeeded(handler: { params in
                    Pixel.fire(pixel: .syncSuccessRateDaily,
                               withAdditionalParameters: params,
                               includedParameters: [.appVersion])
                })
            }

        remoteMessagingClient = RemoteMessagingClient(
            bookmarksDatabase: bookmarksDatabase,
            appSettings: AppDependencyProvider.shared.appSettings,
            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
            configurationStore: AppDependencyProvider.shared.configurationStore,
            database: Database.shared,
            errorEvents: RemoteMessagingStoreErrorHandling(),
            remoteMessagingAvailabilityProvider: PrivacyConfigurationRemoteMessagingAvailabilityProvider(
                privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager
            ),
            duckPlayerStorage: DefaultDuckPlayerStorage()
        )
        remoteMessagingClient.registerBackgroundRefreshTaskHandler()

        subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(
            privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
            purchasePlatform: .appStore)

        subscriptionCookieManager = makeSubscriptionCookieManager()

        homePageConfiguration = HomePageConfiguration(variantManager: AppDependencyProvider.shared.variantManager,
                                                      remoteMessagingClient: remoteMessagingClient,
                                                      privacyProDataReporter: privacyProDataReporter)

        let previewsSource = TabPreviewsSource()
        let historyManager = makeHistoryManager()
        let tabsModel = prepareTabsModel(previewsSource: previewsSource)

        privacyProDataReporter.injectTabsModel(tabsModel)
        
        if shouldPresentInsufficientDiskSpaceAlertAndCrash {

            window = UIWindow(frame: UIScreen.main.bounds)
            window?.rootViewController = BlankSnapshotViewController(appSettings: AppDependencyProvider.shared.appSettings,
                                                                     voiceSearchHelper: voiceSearchHelper)
            window?.makeKeyAndVisible()

            presentInsufficientDiskSpaceAlert()
        } else {
            let daxDialogsFactory = ExperimentContextualDaxDialogsFactory(contextualOnboardingLogic: daxDialogs, contextualOnboardingPixelReporter: onboardingPixelReporter)
            let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
            let main = MainViewController(bookmarksDatabase: bookmarksDatabase,
                                          bookmarksDatabaseCleaner: syncDataProviders.bookmarksAdapter.databaseCleaner,
                                          historyManager: historyManager,
                                          homePageConfiguration: homePageConfiguration,
                                          syncService: syncService,
                                          syncDataProviders: syncDataProviders,
                                          appSettings: AppDependencyProvider.shared.appSettings,
                                          previewsSource: previewsSource,
                                          tabsModel: tabsModel,
                                          syncPausedStateManager: syncErrorHandler,
                                          privacyProDataReporter: privacyProDataReporter,
                                          variantManager: variantManager,
                                          contextualOnboardingPresenter: contextualOnboardingPresenter,
                                          contextualOnboardingLogic: daxDialogs,
                                          contextualOnboardingPixelReporter: onboardingPixelReporter,
                                          subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                          voiceSearchHelper: voiceSearchHelper,
                                          featureFlagger: AppDependencyProvider.shared.featureFlagger,
                                          subscriptionCookieManager: subscriptionCookieManager,
                                          textZoomCoordinator: makeTextZoomCoordinator(),
                                          appDidFinishLaunchingStartTime: didFinishLaunchingStartTime)

            main.loadViewIfNeeded()
            syncErrorHandler.alertPresenter = main

            window = UIWindow(frame: UIScreen.main.bounds)
            window?.rootViewController = main
            window?.makeKeyAndVisible()

            autoClear = AutoClear(worker: main)
            let applicationState = application.applicationState
            Task {
                await autoClear?.clearDataIfEnabled(applicationState: .init(with: applicationState))
                await vpnWorkaround.installRedditSessionWorkaround()
            }
        }

        self.voiceSearchHelper.migrateSettingsFlagIfNecessary()

        // Task handler registration needs to happen before the end of `didFinishLaunching`, otherwise submitting a task can throw an exception.
        // Having both in `didBecomeActive` can sometimes cause the exception when running on a physical device, so registration happens here.
        AppConfigurationFetch.registerBackgroundRefreshTaskHandler()

        UNUserNotificationCenter.current().delegate = self
        
        window?.windowScene?.screenshotService?.delegate = self
        ThemeManager.shared.updateUserInterfaceStyle(window: window)

        appIsLaunching = true

        // Temporary logic for rollout of Autofill as on by default for new installs only
        if AppDependencyProvider.shared.appSettings.autofillIsNewInstallForOnByDefault == nil {
            AppDependencyProvider.shared.appSettings.setAutofillIsNewInstallForOnByDefault()
        }

        NewTabPageIntroMessageSetup().perform()

        widgetRefreshModel.beginObservingVPNStatus()

        AppDependencyProvider.shared.subscriptionManager.loadInitialData()

        setUpAutofillPixelReporter()

        if didCrashDuringCrashHandlersSetUp {
            Pixel.fire(pixel: .crashOnCrashHandlersSetUp)
            didCrashDuringCrashHandlersSetUp = false
        }

        tipKitAppEventsHandler.appDidFinishLaunching()

        return true
    }

    private func makeTextZoomCoordinator() -> TextZoomCoordinator {
        let provider = AppDependencyProvider.shared
        let storage = TextZoomStorage()

        return TextZoomCoordinator(appSettings: provider.appSettings,
                                   storage: storage,
                                   featureFlagger: provider.featureFlagger)
    }

    private func makeSubscriptionCookieManager() -> SubscriptionCookieManaging {
        let subscriptionCookieManager = SubscriptionCookieManager(subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
                                                              currentCookieStore: { [weak self] in
            guard self?.mainViewController?.tabManager.model.hasActiveTabs ?? false else {
                // We shouldn't interact with WebKit's cookie store unless we have a WebView,
                // eventually the subscription cookie will be refreshed on opening the first tab
                return nil
            }

            return WKHTTPCookieStoreWrapper(store: WKWebsiteDataStore.current().httpCookieStore)
        }, eventMapping: SubscriptionCookieManageEventPixelMapping())


        let privacyConfigurationManager = ContentBlocking.shared.privacyConfigurationManager

        // Enable subscriptionCookieManager if feature flag is present
        if privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.setAccessTokenCookieForSubscriptionDomains) {
            subscriptionCookieManager.enableSettingSubscriptionCookie()
        }

        // Keep track of feature flag changes
        subscriptionCookieManagerFeatureFlagCancellable = privacyConfigurationManager.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak privacyConfigurationManager] in
                guard let self, !self.appIsLaunching, let privacyConfigurationManager else { return }

                let isEnabled = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.setAccessTokenCookieForSubscriptionDomains)

                Task { @MainActor [weak self] in
                    if isEnabled {
                        self?.subscriptionCookieManager.enableSettingSubscriptionCookie()
                    } else {
                        await self?.subscriptionCookieManager.disableSettingSubscriptionCookie()
                    }
                }
            }

        return subscriptionCookieManager
    }

    private func makeHistoryManager() -> HistoryManaging {

        let provider = AppDependencyProvider.shared

        switch HistoryManager.make(isAutocompleteEnabledByUser: provider.appSettings.autocomplete,
                                   isRecentlyVisitedSitesEnabledByUser: provider.appSettings.recentlyVisitedSites,
                                   privacyConfigManager: ContentBlocking.shared.privacyConfigurationManager,
                                   tld: provider.storageCache.tld) {

        case .failure(let error):
            Pixel.fire(pixel: .historyStoreLoadFailed, error: error)
            if error.isDiskFull {
                self.presentInsufficientDiskSpaceAlert()
            } else {
                self.presentPreemptiveCrashAlert()
            }
            return NullHistoryManager()

        case .success(let historyManager):
            return historyManager
        }
    }

    private func prepareTabsModel(previewsSource: TabPreviewsSource = TabPreviewsSource(),
                                  appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
                                  isDesktop: Bool = UIDevice.current.userInterfaceIdiom == .pad) -> TabsModel {
        let isPadDevice = UIDevice.current.userInterfaceIdiom == .pad
        let tabsModel: TabsModel
        if AutoClearSettingsModel(settings: appSettings) != nil {
            tabsModel = TabsModel(desktop: isPadDevice)
            tabsModel.save()
            previewsSource.removeAllPreviews()
        } else {
            if let storedModel = TabsModel.get() {
                // Save new model in case of migration
                storedModel.save()
                tabsModel = storedModel
            } else {
                tabsModel = TabsModel(desktop: isPadDevice)
            }
        }
        return tabsModel
    }

    private func presentPreemptiveCrashAlert() {
        Task { @MainActor in
            let alertController = CriticalAlerts.makePreemptiveCrashAlert()
            window?.rootViewController?.present(alertController, animated: true, completion: nil)
        }
    }

    private func presentInsufficientDiskSpaceAlert() {
        let alertController = CriticalAlerts.makeInsufficientDiskSpaceAlert()
        window?.rootViewController?.present(alertController, animated: true, completion: nil)
    }

    private func presentExpiredEntitlementAlert() {
        let alertController = CriticalAlerts.makeExpiredEntitlementAlert { [weak self] in
            self?.mainViewController?.segueToPrivacyPro()
        }
        window?.rootViewController?.present(alertController, animated: true) { [weak self] in
            self?.tunnelDefaults.showEntitlementAlert = false
        }
    }

    private func presentExpiredEntitlementNotificationIfNeeded() {
        let presenter = NetworkProtectionNotificationsPresenterTogglableDecorator(
            settings: AppDependencyProvider.shared.vpnSettings,
            defaults: .networkProtectionGroupDefaults,
            wrappee: NetworkProtectionUNNotificationPresenter()
        )
        presenter.showEntitlementNotification()
    }

    private func cleanUpMacPromoExperiment2() {
        UserDefaults.standard.removeObject(forKey: "com.duckduckgo.ios.macPromoMay23.exp2.cohort")
    }

    private func cleanUpIncrementalRolloutPixelTest() {
        UserDefaults.standard.removeObject(forKey: "network-protection.incremental-feature-flag-test.has-sent-pixel")
    }

    private func clearTmp() {
        let tmp = FileManager.default.temporaryDirectory
        do {
            try FileManager.default.removeItem(at: tmp)
        } catch {
            Logger.general.error("Failed to delete tmp dir")
        }
    }

    private func reportAdAttribution() {
        Task.detached(priority: .background) {
            await AdAttributionPixelReporter.shared.reportAttributionIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !testing else { return }

        defer {
            if let didFinishLaunchingStartTime {
                let launchTime = CFAbsoluteTimeGetCurrent() - didFinishLaunchingStartTime
                Pixel.fire(pixel: .appDidBecomeActiveTime(time: Pixel.Event.BucketAggregation(number: launchTime)),
                           withAdditionalParameters: [PixelParameters.time: String(launchTime)])
            }
        }

        StorageInconsistencyMonitor().didBecomeActive(isProtectedDataAvailable: application.isProtectedDataAvailable)
        syncService.initializeIfNeeded()
        syncDataProviders.setUpDatabaseCleanersIfNeeded(syncService: syncService)

        if !(overlayWindow?.rootViewController is AuthenticationViewController) {
            removeOverlay()
        }
        
        StatisticsLoader.shared.load {
            StatisticsLoader.shared.refreshAppRetentionAtb()
            self.fireAppLaunchPixel()
            self.reportAdAttribution()
            self.onboardingPixelReporter.fireEnqueuedPixelsIfNeeded()
        }
        
        if appIsLaunching {
            appIsLaunching = false
            onApplicationLaunch(application)
        }

        mainViewController?.showBars()
        mainViewController?.didReturnFromBackground()
        
        if !privacyStore.authenticationEnabled {
            showKeyboardOnLaunch()
        }

        if AppConfigurationFetch.shouldScheduleRulesCompilationOnAppLaunch {
            ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
            AppConfigurationFetch.shouldScheduleRulesCompilationOnAppLaunch = false
        }
        AppDependencyProvider.shared.configurationManager.loadPrivacyConfigFromDiskIfNeeded()

        AppConfigurationFetch().start { result in
            self.sendAppLaunchPostback()
            if case .assetsUpdated(let protectionsUpdated) = result, protectionsUpdated {
                ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
            }
        }

        syncService.scheduler.notifyAppLifecycleEvent()
        
        privacyProDataReporter.injectSyncService(syncService)

        fireFailedCompilationsPixelIfNeeded()

        widgetRefreshModel.refreshVPNWidget()

        if tunnelDefaults.showEntitlementAlert {
            presentExpiredEntitlementAlert()
        }

        presentExpiredEntitlementNotificationIfNeeded()

        Task {
            await stopAndRemoveVPNIfNotAuthenticated()
            await refreshShortcuts()
            await vpnWorkaround.installRedditSessionWorkaround()

            if #available(iOS 17.0, *) {
                await VPNSnoozeLiveActivityManager().endSnoozeActivityIfNecessary()
            }
        }

        AppDependencyProvider.shared.subscriptionManager.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in
            if isSubscriptionActive {
                DailyPixel.fire(pixel: .privacyProSubscriptionActive)
            }
        }

        Task {
            await subscriptionCookieManager.refreshSubscriptionCookie()
        }

        let importPasswordsStatusHandler = ImportPasswordsStatusHandler(syncService: syncService)
        importPasswordsStatusHandler.checkSyncSuccessStatus()

        Task {
            await privacyProDataReporter.saveWidgetAdded()
        }

        AppDependencyProvider.shared.persistentPixel.sendQueuedPixels { _ in }
    }

    private func stopAndRemoveVPNIfNotAuthenticated() async {
        // Only remove the VPN if the user is not authenticated, and it's installed:
        guard !accountManager.isUserAuthenticated, await AppDependencyProvider.shared.networkProtectionTunnelController.isInstalled else {
            return
        }

        await AppDependencyProvider.shared.networkProtectionTunnelController.stop()
        await AppDependencyProvider.shared.networkProtectionTunnelController.removeVPN(reason: .didBecomeActiveCheck)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Task { @MainActor in
            await refreshShortcuts()
            await vpnWorkaround.removeRedditSessionWorkaround()
        }
    }

    private func fireAppLaunchPixel() {
        
        WidgetCenter.shared.getCurrentConfigurations { result in
            let paramKeys: [WidgetFamily: String] = [
                .systemSmall: PixelParameters.widgetSmall,
                .systemMedium: PixelParameters.widgetMedium,
                .systemLarge: PixelParameters.widgetLarge
            ]
            
            switch result {
            case .failure(let error):
                Pixel.fire(pixel: .appLaunch, withAdditionalParameters: [
                    PixelParameters.widgetError: "1",
                    PixelParameters.widgetErrorCode: "\((error as NSError).code)",
                    PixelParameters.widgetErrorDomain: (error as NSError).domain
                ], includedParameters: [.appVersion, .atb])
                
            case .success(let widgetInfo):
                let params = widgetInfo.reduce([String: String]()) {
                    var result = $0
                    if let key = paramKeys[$1.family] {
                        result[key] = "1"
                    }
                    return result
                }
                Pixel.fire(pixel: .appLaunch, withAdditionalParameters: params, includedParameters: [.appVersion, .atb])
            }
            
        }
    }

    private func fireFailedCompilationsPixelIfNeeded() {
        let store = FailedCompilationsStore()
        if store.hasAnyFailures {
            DailyPixel.fire(pixel: .compilationFailed, withAdditionalParameters: store.summary) { error in
                guard error != nil else { return }
                store.cleanup()
            }
        }
    }
    
    private func shouldShowKeyboardOnLaunch() -> Bool {
        guard let date = lastBackgroundDate else { return true }
        return Date().timeIntervalSince(date) > AppDelegate.ShowKeyboardOnLaunchThreshold
    }

    private func showKeyboardOnLaunch() {
        guard KeyboardSettings().onAppLaunch && showKeyboardIfSettingOn && shouldShowKeyboardOnLaunch() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mainViewController?.enterSearch()
        }
        showKeyboardIfSettingOn = false
    }
    
    private func onApplicationLaunch(_ application: UIApplication) {
        Task { @MainActor in
            await beginAuthentication()
            initialiseBackgroundFetch(application)
            applyAppearanceChanges()
            refreshRemoteMessages()
        }
    }
    
    private func applyAppearanceChanges() {
        UILabel.appearance(whenContainedInInstancesOf: [UIAlertController.self]).numberOfLines = 0
    }

    /// It's public in order to allow refreshing on demand via Debug menu. Otherwise it shouldn't be called from outside.
    func refreshRemoteMessages() {
        Task {
            try? await remoteMessagingClient.fetchAndProcess(using: remoteMessagingClient.store)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        ThemeManager.shared.updateUserInterfaceStyle()

        Task { @MainActor in
            await beginAuthentication()
            await autoClear?.clearDataIfEnabledAndTimeExpired(applicationState: .active)
            showKeyboardIfSettingOn = true
            syncService.scheduler.resumeSyncQueue()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        displayBlankSnapshotWindow()
        autoClear?.startClearingTimer()
        lastBackgroundDate = Date()
        AppDependencyProvider.shared.autofillLoginSession.endSession()
        suspendSync()
        syncDataProviders.bookmarksAdapter.cancelFaviconsFetching(application)
        privacyProDataReporter.saveApplicationLastSessionEnded()
        resetAppStartTime()
    }

    private func resetAppStartTime() {
        didFinishLaunchingStartTime = nil
        mainViewController?.appDidFinishLaunchingStartTime = nil
    }

    private func suspendSync() {
        if syncService.isSyncInProgress {
            Logger.sync.debug("Sync is in progress. Starting background task to allow it to gracefully complete.")

            var taskID: UIBackgroundTaskIdentifier!
            taskID = UIApplication.shared.beginBackgroundTask(withName: "Cancelled Sync Completion Task") {
                Logger.sync.debug("Forcing background task completion")
                UIApplication.shared.endBackgroundTask(taskID)
            }
            syncDidFinishCancellable?.cancel()
            syncDidFinishCancellable = syncService.isSyncInProgressPublisher.filter { !$0 }
                .prefix(1)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    Logger.sync.debug("Ending background task")
                    UIApplication.shared.endBackgroundTask(taskID)
                }
        }

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        handleShortCutItem(shortcutItem)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Logger.sync.debug("App launched with url \(url.absoluteString)")

        // If showing the onboarding intro ignore deeplinks
        guard mainViewController?.needsToShowOnboardingIntro() == false else {
            return false
        }

        if handleEmailSignUpDeepLink(url) {
            return true
        }

        NotificationCenter.default.post(name: AutofillLoginListAuthenticator.Notifications.invalidateContext, object: nil)

        // The openVPN action handles the navigation stack on its own and does not need it to be cleared
        if url != AppDeepLinkSchemes.openVPN.url {
            mainViewController?.clearNavigationStack()
        }

        Task { @MainActor in
            // Autoclear should have happened by now
            showKeyboardIfSettingOn = false

            if !handleAppDeepLink(app, mainViewController, url) {
                mainViewController?.loadUrlInNewTab(url, reuseExisting: true, inheritedAttribution: nil, fromExternalLink: true)
            }
        }

        return true
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        Logger.lifecycle.debug(#function)

        AppConfigurationFetch().start(isBackgroundFetch: true) { result in
            switch result {
            case .noData:
                completionHandler(.noData)
            case .assetsUpdated:
                completionHandler(.newData)
            }
        }
    }

    func application(_ application: UIApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        return true
    }

    // MARK: private

    private func sendAppLaunchPostback() {
        // Attribution support
        let privacyConfigurationManager = ContentBlocking.shared.privacyConfigurationManager
        if privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .marketplaceAdPostback) {
            marketplaceAdPostbackManager.sendAppLaunchPostback()
        }
    }

    private func cleanUpATBAndAssignVariant(variantManager: VariantManager, daxDialogs: DaxDialogs) {
        let historyMessageManager = HistoryMessageManager()

        AtbAndVariantCleanup.cleanup()
        variantManager.assignVariantIfNeeded { _ in
            // MARK: perform first time launch logic here
            // If it's running UI Tests check if the onboarding should be in a completed state.
            if launchOptionsHandler.isUITesting && launchOptionsHandler.isOnboardingCompleted {
                daxDialogs.dismiss()
            } else {
                daxDialogs.primeForUse()
            }

            // New users don't see the message
            historyMessageManager.dismiss()

            // Setup storage for marketplace postback
            marketplaceAdPostbackManager.updateReturningUserValue()
        }
    }

    private func initialiseBackgroundFetch(_ application: UIApplication) {
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            return
        }

        // BackgroundTasks will automatically replace an existing task in the queue if one with the same identifier is queued, so we should only
        // schedule a task if there are none pending in order to avoid the config task getting perpetually replaced.
        BGTaskScheduler.shared.getPendingTaskRequests { tasks in
            let hasConfigurationTask = tasks.contains { $0.identifier == AppConfigurationFetch.Constants.backgroundProcessingTaskIdentifier }
            if !hasConfigurationTask {
                AppConfigurationFetch.scheduleBackgroundRefreshTask()
            }

            let hasRemoteMessageFetchTask = tasks.contains { $0.identifier == RemoteMessagingClient.Constants.backgroundRefreshTaskIdentifier }
            if !hasRemoteMessageFetchTask {
                RemoteMessagingClient.scheduleBackgroundRefreshTask()
            }
        }
    }
    
    private func displayAuthenticationWindow() {
        guard overlayWindow == nil, let frame = window?.frame else { return }
        overlayWindow = UIWindow(frame: frame)
        overlayWindow?.windowLevel = UIWindow.Level.alert
        overlayWindow?.rootViewController = AuthenticationViewController.loadFromStoryboard()
        overlayWindow?.makeKeyAndVisible()
        window?.isHidden = true
    }
    
    private func displayBlankSnapshotWindow() {
        guard overlayWindow == nil, let frame = window?.frame else { return }
        guard autoClear?.isClearingEnabled ?? false || privacyStore.authenticationEnabled else { return }
        
        overlayWindow = UIWindow(frame: frame)
        overlayWindow?.windowLevel = UIWindow.Level.alert
        
        let overlay = BlankSnapshotViewController(appSettings: AppDependencyProvider.shared.appSettings, voiceSearchHelper: voiceSearchHelper)
        overlay.delegate = self

        overlayWindow?.rootViewController = overlay
        overlayWindow?.makeKeyAndVisible()
        window?.isHidden = true
    }

    private func beginAuthentication() async {
        
        guard privacyStore.authenticationEnabled else { return }

        removeOverlay()
        displayAuthenticationWindow()
        
        guard let controller = overlayWindow?.rootViewController as? AuthenticationViewController else {
            removeOverlay()
            return
        }
        
        await controller.beginAuthentication { [weak self] in
            self?.removeOverlay()
            self?.showKeyboardOnLaunch()
        }
    }
    
    private func tryToObtainOverlayWindow() {
        for window in UIApplication.shared.foregroundSceneWindows where window.rootViewController is BlankSnapshotViewController {
            overlayWindow = window
            return
        }
    }

    private func removeOverlay() {
        if overlayWindow == nil {
            tryToObtainOverlayWindow()
        }

        if let overlay = overlayWindow {
            overlay.isHidden = true
            overlayWindow = nil
            window?.makeKeyAndVisible()
        }
    }

    private func handleShortCutItem(_ shortcutItem: UIApplicationShortcutItem) {
        Logger.general.debug("Handling shortcut item: \(shortcutItem.type)")

        Task { @MainActor in

            if appIsLaunching {
                await autoClear?.clearDataIfEnabled()
            } else {
                await autoClear?.clearDataIfEnabledAndTimeExpired(applicationState: .active)
            }

            if shortcutItem.type == ShortcutKey.clipboard, let query = UIPasteboard.general.string {
                mainViewController?.clearNavigationStack()
                mainViewController?.loadQueryInNewTab(query)
                return
            }

            if shortcutItem.type == ShortcutKey.passwords {
                mainViewController?.clearNavigationStack()
                // Give the `clearNavigationStack` call time to complete.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) { [weak self] in
                    self?.mainViewController?.launchAutofillLogins(openSearch: true, source: .appIconShortcut)
                }
                Pixel.fire(pixel: .autofillLoginsLaunchAppShortcut)
                return
            }

            if shortcutItem.type == ShortcutKey.openVPNSettings {
                presentNetworkProtectionStatusSettingsModal()
            }

        }
    }

    private func removeEmailWaitlistState() {
        EmailWaitlist.removeEmailState()

        let autofillStorage = EmailKeychainManager()
        try? autofillStorage.deleteWaitlistState()

        // Remove the authentication state if this is a fresh install.
        if !Database.shared.isDatabaseFileInitialized {
            try? autofillStorage.deleteAuthenticationState()
        }
    }

    private func handleEmailSignUpDeepLink(_ url: URL) -> Bool {
        guard url.absoluteString.starts(with: URL.emailProtection.absoluteString),
              let navViewController = mainViewController?.presentedViewController as? UINavigationController,
              let emailSignUpViewController = navViewController.topViewController as? EmailSignupViewController else {
            return false
        }
        emailSignUpViewController.loadUrl(url)
        return true
    }

    private var mainViewController: MainViewController? {
        return window?.rootViewController as? MainViewController
    }

    private func setUpAutofillPixelReporter() {
        autofillPixelReporter = AutofillPixelReporter(
            userDefaults: .standard,
            autofillEnabled: AppDependencyProvider.shared.appSettings.autofillCredentialsEnabled,
            eventMapping: EventMapping<AutofillPixelEvent> {event, _, params, _ in
                switch event {
                case .autofillActiveUser:
                    Pixel.fire(pixel: .autofillActiveUser)
                case .autofillEnabledUser:
                    Pixel.fire(pixel: .autofillEnabledUser)
                case .autofillOnboardedUser:
                    Pixel.fire(pixel: .autofillOnboardedUser)
                case .autofillToggledOn:
                    Pixel.fire(pixel: .autofillToggledOn, withAdditionalParameters: params ?? [:])
                case .autofillToggledOff:
                    Pixel.fire(pixel: .autofillToggledOff, withAdditionalParameters: params ?? [:])
                case .autofillLoginsStacked:
                    Pixel.fire(pixel: .autofillLoginsStacked, withAdditionalParameters: params ?? [:])
                default:
                    break
                }
            },
            installDate: StatisticsUserDefaults().installDate ?? Date())
        
        _ = NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.autofillEnabledChange,
                                                   object: nil,
                                                   queue: nil) { [weak self] _ in
            self?.autofillPixelReporter?.updateAutofillEnabledStatus(AppDependencyProvider.shared.appSettings.autofillCredentialsEnabled)
        }
    }

    @MainActor
    func refreshShortcuts() async {
        guard AppDependencyProvider.shared.vpnFeatureVisibility.shouldShowVPNShortcut() else {
            UIApplication.shared.shortcutItems = nil
            return
        }

        if case .success(true) = await accountManager.hasEntitlement(forProductName: .networkProtection, cachePolicy: .returnCacheDataDontLoad) {
            let items = [
                UIApplicationShortcutItem(type: ShortcutKey.openVPNSettings,
                                          localizedTitle: UserText.netPOpenVPNQuickAction,
                                          localizedSubtitle: nil,
                                          icon: UIApplicationShortcutIcon(templateImageName: "VPN-16"),
                                          userInfo: nil)
            ]

            UIApplication.shared.shortcutItems = items
        } else {
            UIApplication.shared.shortcutItems = nil
        }
    }
}

extension AppDelegate: BlankSnapshotViewRecoveringDelegate {
    
    func recoverFromPresenting(controller: BlankSnapshotViewController) {
        if overlayWindow == nil {
            tryToObtainOverlayWindow()
        }
        
        overlayWindow?.isHidden = true
        overlayWindow = nil
        window?.makeKeyAndVisible()
    }
    
}

extension AppDelegate: UIScreenshotServiceDelegate {
    func screenshotService(_ screenshotService: UIScreenshotService,
                           generatePDFRepresentationWithCompletion completionHandler: @escaping (Data?, Int, CGRect) -> Void) {
        guard let webView = mainViewController?.currentTab?.webView else {
            completionHandler(nil, 0, .zero)
            return
        }

        let zoomScale = webView.scrollView.zoomScale

        // The PDF's coordinate space has its origin at the bottom left, so the view's origin.y needs to be converted
        let visibleBounds = CGRect(
            x: webView.scrollView.contentOffset.x / zoomScale,
            y: (webView.scrollView.contentSize.height - webView.scrollView.contentOffset.y - webView.bounds.height) / zoomScale,
            width: webView.bounds.width / zoomScale,
            height: webView.bounds.height / zoomScale
        )

        webView.createPDF { result in
            let data = try? result.get()
            completionHandler(data, 0, visibleBounds)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.banner)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let identifier = response.notification.request.identifier

            if NetworkProtectionNotificationIdentifier(rawValue: identifier) != nil {
                presentNetworkProtectionStatusSettingsModal()
            }
        }

        completionHandler()
    }

    func presentNetworkProtectionStatusSettingsModal() {
        Task {
            if case .success(let hasEntitlements) = await accountManager.hasEntitlement(forProductName: .networkProtection), hasEntitlements {
                (window?.rootViewController as? MainViewController)?.segueToVPN()
            } else {
                (window?.rootViewController as? MainViewController)?.segueToPrivacyPro()
            }
        }
    }

    private func presentSettings(with viewController: UIViewController) {
        guard let window = window, let rootViewController = window.rootViewController as? MainViewController else { return }

        if let navigationController = rootViewController.presentedViewController as? UINavigationController {
            if let lastViewController = navigationController.viewControllers.last, lastViewController.isKind(of: type(of: viewController)) {
                // Avoid presenting dismissing and re-presenting the view controller if it's already visible:
                return
            } else {
                // Otherwise, replace existing view controllers with the presented one:
                navigationController.popToRootViewController(animated: false)
                navigationController.pushViewController(viewController, animated: false)
                return
            }
        }

        // If the previous checks failed, make sure the nav stack is reset and present the view controller from scratch:
        rootViewController.clearNavigationStack()

        // Give the `clearNavigationStack` call time to complete.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            rootViewController.segueToSettings()
            let navigationController = rootViewController.presentedViewController as? UINavigationController
            navigationController?.popToRootViewController(animated: false)
            navigationController?.pushViewController(viewController, animated: false)
        }
    }
}

extension DataStoreWarmup.ApplicationState {

    init(with state: UIApplication.State) {
        switch state {
        case .inactive:
            self = .inactive
        case .active:
            self = .active
        case .background:
            self = .background
        @unknown default:
            self = .unknown
        }
    }
}

private extension Error {

    var isDiskFull: Bool {
        let nsError = self as NSError
        if let underlyingError = nsError.userInfo["NSUnderlyingError"] as? NSError, underlyingError.code == 13 {
            return true
        }

        if nsError.userInfo["NSSQLiteErrorDomain"] as? Int == 13 {
            return true
        }
        
        return false
    }

}
