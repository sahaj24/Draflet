import SwiftUI
import ServiceManagement

// MARK: - User Settings
class UserSettings: ObservableObject {
    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        }
    }

    @Published var startupOnLogin: Bool {
        didSet {
            UserDefaults.standard.set(startupOnLogin, forKey: "startupOnLogin")
        }
    }

    @Published var soundEffects: Bool {
        didSet {
            UserDefaults.standard.set(soundEffects, forKey: "soundEffects")
        }
    }
    
    @Published var defaultAction: AIAction {
        didSet {
            UserDefaults.standard.set(defaultAction.rawValue, forKey: "defaultAction")
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }
    
    @Published var selectedCustomPromptId: UUID? {
        didSet {
            if let id = selectedCustomPromptId {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedCustomPromptId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedCustomPromptId")
            }
        }
    }
    
    @Published var useSmartPrompt: Bool {
        didSet {
            UserDefaults.standard.set(useSmartPrompt, forKey: "useSmartPrompt")
        }
    }

    @Published var shortcutKeyCode: Int {
        didSet {
            UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode")
        }
    }

    @Published var shortcutModifiers: [String] {
        didSet {
            UserDefaults.standard.set(shortcutModifiers, forKey: "shortcutModifiers")
        }
    }
    
    @Published var promptShortcuts: [String: PromptShortcut] {
        didSet {
            if let encoded = try? JSONEncoder().encode(promptShortcuts) {
                UserDefaults.standard.set(encoded, forKey: "promptShortcuts")
            }
        }
    }
    
    @Published var isAdmin: Bool {
        didSet {
            UserDefaults.standard.set(isAdmin, forKey: "isAdmin")
        }
    }

    init() {
        // Load theme
        if let themeRaw = UserDefaults.standard.string(forKey: "theme"),
           let loadedTheme = Theme(rawValue: themeRaw) {
            self.theme = loadedTheme
        } else {
            self.theme = Theme.dark
        }
        
        self.startupOnLogin = UserDefaults.standard.bool(forKey: "startupOnLogin")
        self.soundEffects = (UserDefaults.standard.object(forKey: "soundEffects") as? Bool) ?? true
        if let actionRaw = UserDefaults.standard.string(forKey: "defaultAction"),
           let action = AIAction(rawValue: actionRaw) {
            self.defaultAction = action
        } else {
            self.defaultAction = .fixGrammar
        }

        // Load custom prompts
        if let data = UserDefaults.standard.data(forKey: "customPrompts"),
           let decoded = try? JSONDecoder().decode([CustomPrompt].self, from: data) {
            self.customPrompts = decoded
        } else {
            // Migrate old single custom prompt if exists
            let oldPrompt = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? ""
            if !oldPrompt.isEmpty {
                self.customPrompts = [CustomPrompt(name: "Custom Prompt", content: oldPrompt)]
            } else {
                self.customPrompts = []
            }
        }
        
        // Load selected custom prompt
        if let idString = UserDefaults.standard.string(forKey: "selectedCustomPromptId"),
           let id = UUID(uuidString: idString) {
            self.selectedCustomPromptId = id
        }
        
        self.useSmartPrompt = UserDefaults.standard.bool(forKey: "useSmartPrompt")

        let storedKeyCode = UserDefaults.standard.object(forKey: "shortcutKeyCode") as? Int
        self.shortcutKeyCode = storedKeyCode ?? 0

        let storedModifiers = UserDefaults.standard.array(forKey: "shortcutModifiers") as? [String]
        self.shortcutModifiers = (storedModifiers?.isEmpty == false) ? (storedModifiers ?? ["command", "shift"]) : ["command", "shift"]
        
        // Load prompt shortcuts
        if let data = UserDefaults.standard.data(forKey: "promptShortcuts"),
           let decoded = try? JSONDecoder().decode([String: PromptShortcut].self, from: data) {
            self.promptShortcuts = decoded
        } else {
            self.promptShortcuts = [:]
        }
        
        // Load admin status
        self.isAdmin = UserDefaults.standard.bool(forKey: "isAdmin")
    }
}

// MARK: - Prompt Shortcut
struct PromptShortcut: Codable {
    let actionId: String
    let keyCode: Int
    let modifiers: [String]
}

// MARK: - AIWritingAssistantApp
@main
struct AIWritingAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var floatingWindowController: FloatingWindowController?
    var shortcutManager: ShortcutManager?
    var textManager: TextCaptureManager?
    var aiService: AIService?
    var usageTracker: UsageTracker
    var statusItem: NSStatusItem?
    var mainWindowController: NSWindowController?
    var loginWindowController: NSWindowController?
    var onboardingWindowController: NSWindowController?
    var userSettings = UserSettings()
    private let successSoundName = "Glass"
    
    override init() {
        self.usageTracker = UsageTracker()
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupGlobalShortcut()
        setupMenuBar()
        setupAuthObserver()
    }
    
    // Handle deep links from website login
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url: url)
        }
    }
    
    private func handleDeepLink(url: URL) {
        // Handle aiwriting://callback?token=xxx&refresh_token=xxx
        guard url.scheme == "aiwriting",
              url.host == "callback" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        var accessToken: String?
        var refreshToken: String?
        var expiresIn: Int = 3600
        var userId: String?
        var email: String?
        var displayName: String?
        var avatarUrl: String?
        var plan: String = "free"
        
        for item in queryItems {
            switch item.name {
            case "access_token":
                accessToken = item.value
            case "refresh_token":
                refreshToken = item.value
            case "expires_in":
                expiresIn = Int(item.value ?? "3600") ?? 3600
            case "user_id":
                userId = item.value
            case "email":
                email = item.value
            case "display_name":
                displayName = item.value
            case "avatar_url":
                avatarUrl = item.value
            case "plan":
                plan = item.value ?? "free"
            default:
                break
            }
        }
        
        guard let accessToken = accessToken,
              let refreshToken = refreshToken,
              let userId = userId else {
            showLoginError()
            return
        }
        
        // Create session
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        let session = UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            plan: plan
        )
        
        // Save and activate session
        AuthManager.shared.currentUser = session
        AuthManager.shared.isAuthenticated = true
        AuthManager.shared.saveSession(session)
        
        // Trigger auth state change to show main window
        NotificationCenter.default.post(name: NSNotification.Name("AuthStateChanged"), object: nil)
    }
    
    private func showLoginError() {
        ToastNotificationManager.shared.showToast(
            message: "Login failed",
            subtitle: "Could not complete sign in. Please try again.",
            type: .error,
            duration: 4.0
        )
    }
    
    private func setupAuthObserver() {
        // Observe auth state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthStateChange),
            name: NSNotification.Name("AuthStateChanged"),
            object: nil
        )
    }
    
    @objc private func handleAuthStateChange() {
        DispatchQueue.main.async {
            if AuthManager.shared.isAuthenticated {
                // Close login window
                self.loginWindowController?.close()
                self.loginWindowController = nil
                
                // Check if onboarding is needed
                let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
                if !hasCompletedOnboarding {
                    // Keep main window hidden while onboarding is pending to avoid UI flicker.
                    self.mainWindowController?.close()
                    self.mainWindowController = nil
                    self.showOnboardingWindow()
                } else {
                    self.onboardingWindowController?.close()
                    self.onboardingWindowController = nil
                    self.showMainWindow()
                }
            } else {
                // Close main window and onboarding and show login
                self.mainWindowController?.close()
                self.mainWindowController = nil
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
                self.showLoginWindow()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager?.stopListening()
    }
    
    private func setupServices() {
        aiService = AIService()
        textManager = TextCaptureManager()
    }
    
    private func setupGlobalShortcut() {
        shortcutManager = ShortcutManager()
        shortcutManager?.updateShortcut(
            keyCode: userSettings.shortcutKeyCode,
            modifiers: userSettings.shortcutModifiers
        )
        shortcutManager?.updatePromptShortcuts(userSettings.promptShortcuts)
        shortcutManager?.onShortcutTriggered = { [weak self] promptId in
            self?.handleGlobalShortcut(promptId: promptId)
        }
        shortcutManager?.startListening()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = makeStatusBarLogoImage()
            button.action = #selector(showMainWindow)
            button.target = self
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open", action: #selector(showMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    private func makeStatusBarLogoImage() -> NSImage? {
        let image = resolveDraftletLogoImage()
        image?.size = NSSize(width: 18, height: 18)
        // Template mode lets macOS render the icon with correct contrast in the menu bar.
        image?.isTemplate = true
        return image
    }

    private func resolveDraftletLogoImage() -> NSImage? {
#if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "draftlet-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
#endif
        if let image = NSImage(named: "draftlet-logo") {
            return image
        }
        if let url = Bundle.main.url(forResource: "draftlet-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
    
    private func handleGlobalShortcut(promptId: String? = nil) {
        guard let textManager = textManager else { return }
        
        textManager.captureTextOrCurrentLine { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let captured):
                    self?.autoExecute(text: captured.text, forcedPromptId: promptId)
                case .failure(let error):
                    self?.handleCaptureError(error)
                }
            }
        }
    }
    
    private func autoExecute(text: String, forcedPromptId: String? = nil) {
        guard let aiService = aiService else { return }
        
        let action: AIAction
        let customPrompt: String?
        
        if let forcedPromptId,
           let forcedPrompt = userSettings.customPrompts.first(where: { $0.id.uuidString == forcedPromptId }) {
            action = .custom
            customPrompt = forcedPrompt.content
        } else if userSettings.useSmartPrompt {
            action = .smartPrompt
            customPrompt = nil
        } else if let selectedId = userSettings.selectedCustomPromptId,
                  let prompt = userSettings.customPrompts.first(where: { $0.id == selectedId }) {
            action = .custom
            customPrompt = prompt.content
        } else {
            action = userSettings.defaultAction
            customPrompt = nil
        }
        
        aiService.rewriteText(
            text,
            action: action,
            customSystemPrompt: customPrompt
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rewrittenText):
                    self?.textManager?.replaceSelectedText(with: rewrittenText) { replaceResult in
                        if case .success = replaceResult {
                            self?.usageTracker.recordUsage(
                                action: action,
                                originalText: text,
                                rewrittenText: rewrittenText,
                                model: "llama-3.3-70b-versatile"
                            )
                            self?.playSuccessSoundIfEnabled()
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.playFailureSoundIfEnabled()
                        self?.showError(error: error)
                    }
                }
            }
        }
    }

    private func playSuccessSoundIfEnabled() {
        guard userSettings.soundEffects else { return }
        NSSound(named: NSSound.Name(successSoundName))?.play()
    }

    private func playFailureSoundIfEnabled() {
        guard userSettings.soundEffects else { return }
        NSSound(named: NSSound.Name("Basso"))?.play()
    }
    
    private func showError(error: AIServiceError) {
        DispatchQueue.main.async {
            let message: String
            switch error {
            case .networkError:
                message = "Unable to connect to AI service"
            case .apiError(let msg):
                message = msg
            case .rateLimited:
                message = "Too many requests. Please wait a moment"
            case .insufficientTokens(let remaining):
                message = "Insufficient tokens. You have \(remaining) remaining. Upgrade to Pro for more."
            default:
                message = "Something went wrong. Please try again"
            }
            
            ToastNotificationManager.shared.showToast(
                message: "AI Error",
                subtitle: message,
                type: .error,
                duration: 4.0
            )
        }
    }
    
    private func handleCaptureError(_ error: TextCaptureError) {
        switch error {
        case .noSelection:
            ToastNotificationManager.shared.showToast(
                message: "No text selected",
                subtitle: "Please select some text or place cursor in a paragraph",
                type: .warning,
                duration: 3.0
            )
        case .accessibilityDenied:
            ToastNotificationManager.shared.showToast(
                message: "Accessibility access required",
                subtitle: "Enable in System Settings > Privacy & Security > Accessibility",
                type: .error,
                duration: 5.0
            )
        case .captureFailed:
            ToastNotificationManager.shared.showToast(
                message: "Text capture failed",
                subtitle: "Try selecting text again or place cursor in a paragraph",
                type: .warning,
                duration: 3.0
            )
        case .replacementFailed:
            ToastNotificationManager.shared.showToast(
                message: "Text replacement failed",
                subtitle: "Please try again",
                type: .warning,
                duration: 3.0
            )
        }
        
        playFailureSoundIfEnabled()
    }
    
    @MainActor
    @objc func showMainWindow() {
        // Check if user is authenticated
        if !AuthManager.shared.isAuthenticated {
            showLoginWindow()
            return
        }

        // Never show main content before onboarding is completed.
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            showOnboardingWindow()
            return
        }
        
        if mainWindowController == nil {
            let mainView = MainWindowView(
                usageTracker: usageTracker,
                shortcutManager: shortcutManager,
                userSettings: userSettings
            )
            let hostingController = NSHostingController(rootView: mainView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Draftlet"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            let isDark = userSettings.theme == Theme.dark || (userSettings.theme == Theme.system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            window.backgroundColor = isDark
                ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
                : NSColor(red: 0.9921569, green: 0.9921569, blue: 0.9843137, alpha: 1.0)
            window.contentViewController = hostingController
            adjustTrafficLightPosition(for: window, xOffset: 8)
            window.minSize = NSSize(width: 700, height: 500)
            window.center()
            
            mainWindowController = NSWindowController(window: window)
        }
        
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    private func showLoginWindow() {
        if loginWindowController == nil {
            let loginView = LoginView()
            let hostingController = NSHostingController(rootView: loginView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign In"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.backgroundColor = NSColor(red: 0.898, green: 0.898, blue: 0.882, alpha: 1.0)
            window.contentViewController = hostingController
            adjustTrafficLightPosition(for: window, xOffset: 8)
            window.center()
            window.isMovableByWindowBackground = true
            
            loginWindowController = NSWindowController(window: window)
        }
        
        loginWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    private func showOnboardingWindow() {
        if onboardingWindowController == nil {
            @State var isOnboardingComplete = false
            let onboardingView = OnboardingView(isOnboardingComplete: Binding(
                get: { isOnboardingComplete },
                set: { newValue in
                    isOnboardingComplete = newValue
                    if newValue {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        DispatchQueue.main.async {
                            self.onboardingWindowController?.close()
                            self.onboardingWindowController = nil
                            self.showMainWindow()
                        }
                    }
                }
            ))
            let hostingController = NSHostingController(rootView: onboardingView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentViewController = hostingController
            window.center()
            window.isMovableByWindowBackground = true
            
            onboardingWindowController = NSWindowController(window: window)
        }
        
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    @objc func showSettings() {
        showMainWindow()
    }

    private func adjustTrafficLightPosition(for window: NSWindow, xOffset: CGFloat) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            var frame = button.frame
            frame.origin.x += xOffset
            button.setFrameOrigin(frame.origin)
        }
    }
}

// MARK: - MainWindowView
struct MainWindowView: View {
    @ObservedObject var usageTracker: UsageTracker
    var shortcutManager: ShortcutManager?
    @ObservedObject var userSettings: UserSettings
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var tokenManager = TokenManager.shared
    
    @State private var selectedSection: SectionType = .general
    @State private var selectedEntry: UsageEntry?
    @State private var searchText: String = ""
    @State private var showSignOutConfirmation: Bool = false
    @State private var showTokenEditSheet: Bool = false
    @State private var editTokenAmount: String = ""
    
    // Dynamic colors based on theme
    private var accentColor: Color {
        Color(NSColor(red: 0.55, green: 0.32, blue: 0.22, alpha: 1.0)) // Brown/red accent for dark mode
    }
    
    private var textColor: Color {
        isDarkMode ? Color.white : Color(NSColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0))
    }
    
    private var mutedColor: Color {
        isDarkMode ? Color.gray.opacity(0.7) : Color(NSColor(red: 0.48, green: 0.45, blue: 0.42, alpha: 1.0))
    }
    
    private var creamBg: Color {
        isDarkMode ? Color(NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)) : Color(NSColor(red: 0.9921569, green: 0.9921569, blue: 0.9843137, alpha: 1.0))
    }
    
    private var sidebarBg: Color {
        isDarkMode ? Color(NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0)) : Color(NSColor(red: 0.9568627, green: 0.9568627, blue: 0.9333333, alpha: 1.0))
    }
    
    private var selectedBg: Color {
        isDarkMode ? Color.white.opacity(0.1) : Color(NSColor(red: 0.95, green: 0.945, blue: 0.935, alpha: 1.0))
    }
    
    private var isDarkMode: Bool {
        switch userSettings.theme {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch userSettings.theme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil // Let system handle it
        }
    }
    
    // User profile computed properties
    private var userDisplayName: String {
        authManager.currentUser?.displayName ?? 
        authManager.currentUser?.email?.components(separatedBy: "@").first ?? 
        "User"
    }
    
    private var userInitials: String {
        let name = userDisplayName
        let components = name.split(separator: " ")
        if components.count > 1 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private var userPlanDisplay: String {
        let plan = authManager.currentUser?.plan ?? "free"
        return plan.capitalized + " Plan"
    }
    
    // Token display computed properties
    private var tokenColor: Color {
        if tokenManager.tokensRemaining == 0 {
            return Color.red
        } else if tokenManager.tokensRemaining <= 5 {
            return Color.orange
        } else {
            return Color(NSColor(red: 0.25, green: 0.65, blue: 0.35, alpha: 1.0))
        }
    }
    
    private var isAdmin: Bool {
        // Simple check - in production, use proper admin verification
        userSettings.isAdmin
    }
    
    private func signOut() {
        authManager.signOut()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            let titlebarHeight: CGFloat = 36

            HStack(spacing: 0) {
                sidebarBg
                    .frame(width: 220, height: titlebarHeight)

                creamBg
                    .frame(maxWidth: .infinity, maxHeight: titlebarHeight)
            }
            .frame(height: titlebarHeight)
            .overlay(
                Rectangle()
                    .fill(isDarkMode ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                    .frame(height: 1),
                alignment: .bottom
            )

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SectionType.allCases, id: \.self) { section in
                        SidebarItem(
                            icon: section.icon,
                            title: section.title,
                            isSelected: selectedSection == section,
                            accentColor: accentColor,
                            textColor: textColor,
                            mutedColor: mutedColor,
                            selectedBg: selectedBg
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSection = section
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                Spacer()
                
                HStack(spacing: 10) {
                    // User avatar
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        
                        if let avatarUrl = authManager.currentUser?.avatarUrl,
                           let _ = URL(string: avatarUrl) {
                            // In production, load actual avatar image
                            Text(userInitials)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(accentColor)
                        } else {
                            Text(userInitials)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(userDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(textColor)
                        
                        // Token display - clickable to edit
                        Button(action: {
                            if isAdmin {
                                editTokenAmount = String(tokenManager.tokensRemaining)
                                showTokenEditSheet = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(tokenColor)
                                Text("\(tokenManager.tokensUsedToday)/\(tokenManager.dailyLimit)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(tokenColor)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tokenColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(isAdmin ? "Click to edit tokens (Admin)" : "Tokens used today")
                        .onAppear {
                            Task {
                                await tokenManager.fetchTokens()
                            }
                        }
                        Text(userPlanDisplay)
                            .font(.system(size: 10))
                            .foregroundColor(mutedColor)
                    }
                    
                    Spacer()
                    
                    // Sign out button - minimal aesthetic
                    Button(action: {
                        showSignOutConfirmation = true
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(mutedColor)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.gray.opacity(0.12))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Log Out")
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            // Hover effect handled by SwiftUI automatically
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(sidebarBg.opacity(0.8))
                }
                .frame(width: 220)
                .background(sidebarBg)

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(creamBg)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(colorScheme)
        .onChange(of: userSettings.theme) { _ in
            updateWindowAppearance()
        }
        .confirmationDialog("Log out from Draftlet?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will return to the sign-in screen.")
        }
        .sheet(isPresented: $showTokenEditSheet) {
            TokenEditSheet(
                tokenAmount: $editTokenAmount,
                currentTokens: tokenManager.tokensRemaining,
                onSave: { newAmount in
                    Task {
                        let success = await tokenManager.adminSetTokens(amount: newAmount)
                        if success {
                            ToastNotificationManager.shared.showToast(
                                message: "Tokens updated",
                                subtitle: "Set to \(newAmount) tokens",
                                type: .success,
                                duration: 2.0
                            )
                        }
                    }
                },
                onCancel: {
                    showTokenEditSheet = false
                }
            )
        }
    }
    
    private func updateWindowAppearance() {
        // Update window background color based on theme
        if let window = NSApplication.shared.mainWindow {
            window.backgroundColor = isDarkMode 
                ? NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
                : NSColor(red: 0.9921569, green: 0.9921569, blue: 0.9843137, alpha: 1.0)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .general:
            GeneralView(userSettings: userSettings, accentColor: accentColor, textColor: textColor, mutedColor: mutedColor)
        case .shortcuts:
            ShortcutsView(
                shortcutManager: shortcutManager,
                userSettings: userSettings,
                accentColor: accentColor,
                textColor: textColor,
                mutedColor: mutedColor,
                creamBg: creamBg
            )
        case .history:
            HistoryView(usageTracker: usageTracker, accentColor: accentColor, textColor: textColor, mutedColor: mutedColor, creamBg: creamBg, sidebarBg: sidebarBg, isDarkMode: isDarkMode)
        case .systemPrompt:
            SystemPromptView(userSettings: userSettings, accentColor: accentColor, textColor: textColor, mutedColor: mutedColor, creamBg: creamBg)
        case .usage:
            UsageView(usageTracker: usageTracker, accentColor: accentColor, textColor: textColor, mutedColor: mutedColor, creamBg: creamBg)
        }
    }
}

// MARK: - Sidebar Item
struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let selectedBg: Color
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? accentColor : mutedColor)
                    .frame(width: 24, alignment: .center)
                
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? textColor : mutedColor)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? selectedBg : (isHovered ? selectedBg.opacity(0.6) : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Section Types
enum SectionType: String, CaseIterable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case history = "History"
    case systemPrompt = "System Prompt"
    case usage = "Usage"
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .history: return "clock"
        case .systemPrompt: return "text.bubble"
        case .usage: return "chart.bar.fill"
        }
    }
}

// MARK: - General View
struct GeneralView: View {
    @ObservedObject var userSettings: UserSettings
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("General")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(textColor)
                
                // Appearance Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Appearance")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(textColor)
                    
                    Text("Customize how Draftlet looks on your desktop.")
                        .font(.system(size: 13))
                        .foregroundColor(mutedColor)
                    
                    HStack(spacing: 16) {
                        // Light Theme Card
                        ThemeCard(
                            theme: Theme.light,
                            isSelected: userSettings.theme == Theme.light,
                            accentColor: accentColor,
                            textColor: textColor
                        ) {
                            userSettings.theme = Theme.light
                        }
                        
                        // Dark Theme Card
                        ThemeCard(
                            theme: Theme.dark,
                            isSelected: userSettings.theme == Theme.dark,
                            accentColor: accentColor,
                            textColor: textColor
                        ) {
                            userSettings.theme = Theme.dark
                        }
                        
                        // System Theme Card
                        ThemeCard(
                            theme: Theme.system,
                            isSelected: userSettings.theme == Theme.system,
                            accentColor: accentColor,
                            textColor: textColor
                        ) {
                            userSettings.theme = Theme.system
                        }
                    }
                }
                
                // App Behavior Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("App Behavior")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(textColor)
                    
                    Text("Manage system-level interactions and notifications.")
                        .font(.system(size: 13))
                        .foregroundColor(mutedColor)
                    
                    VStack(spacing: 0) {
                        ModernToggleRow(
                            title: "Start at Login",
                            subtitle: "Automatically launch the app when you sign in",
                            isOn: $userSettings.startupOnLogin,
                            accentColor: accentColor,
                            textColor: textColor,
                            mutedColor: mutedColor
                        )
                        
                        Divider()
                            .padding(.horizontal, 16)
                        
                        ModernToggleRow(
                            title: "Sound Effects",
                            subtitle: "Play subtle sounds for AI responses",
                            isOn: $userSettings.soundEffects,
                            accentColor: accentColor,
                            textColor: textColor,
                            mutedColor: mutedColor
                        )
                    }
                    .background(isDarkMode ? Color(NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)) : Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                }
                
                Spacer()
            }
            .padding(32)
        }
        .background(creamBg)
    }
    
    private var isDarkMode: Bool {
        userSettings.theme == Theme.dark || (userSettings.theme == Theme.system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    
    private var creamBg: Color {
        isDarkMode ? Color(NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)) : Color(NSColor(red: 0.9921569, green: 0.9921569, blue: 0.9843137, alpha: 1.0))
    }
}

// MARK: - Theme Card
struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Visual Preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeBackgroundColor)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                
                // Mock UI lines inside preview
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeLineColor.opacity(0.4))
                        .frame(width: 40, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeLineColor.opacity(0.3))
                        .frame(width: 60, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeLineColor.opacity(0.2))
                        .frame(width: 50, height: 4)
                }
                .padding(.horizontal, 12)
            }
            
            // Label and Radio Button
            HStack {
                Text(theme.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : Color.gray.opacity(0.4), lineWidth: 2)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .frame(width: 100)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
    
    private var themeBackgroundColor: Color {
        switch theme {
        case .light:
            return Color(NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1.0))
        case .dark:
            return Color(NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0))
        case .system:
            return Color(NSColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1.0)) // Shows split in mock
        }
    }
    
    private var themeLineColor: Color {
        switch theme {
        case .light:
            return Color.gray
        case .dark:
            return Color.white
        case .system:
            return Color.gray
        }
    }
}

// MARK: - Modern Toggle Row
struct ModernToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textColor)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(mutedColor)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: accentColor))
                .labelsHidden()
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accentColor: Color
    let textColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textColor)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor(red: 0.48, green: 0.45, blue: 0.42, alpha: 1.0)))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: accentColor))
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

struct SettingSection<Content: View>: View {
    let title: String
    let accentColor: Color
    let cardBg: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accentColor.opacity(0.7))
                .tracking(0.5)
            
            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background(cardBg)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - Shortcuts View
struct ShortcutsView: View {
    var shortcutManager: ShortcutManager?
    @ObservedObject var userSettings: UserSettings
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let creamBg: Color

    private let keyOptions: [(label: String, code: Int)] = [
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3),
        ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40), ("L", 37),
        ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15),
        ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
        ("Y", 16), ("Z", 6), ("Space", 49)
    ]
    
    @State private var selectedPromptForShortcut: CustomPrompt?
    @State private var editingShortcutKey: Int = 0
    @State private var editingShortcutModifiers: [String] = ["command"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Shortcuts")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(textColor)
                
                // Global Shortcut Section
                SettingSection(title: "Global Shortcut", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Default Shortcut")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(textColor)
                                Text("Press anywhere to activate Draftlet")
                                    .font(.system(size: 12))
                                    .foregroundColor(mutedColor)
                            }

                            Spacer()

                            Text(shortcutManager?.shortcutDescription() ?? "⌘⇧A")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(accentColor.opacity(0.1))
                                .cornerRadius(6)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Key")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(mutedColor)
                                Picker("Key", selection: $userSettings.shortcutKeyCode) {
                                    ForEach(keyOptions, id: \.code) { option in
                                        Text(option.label).tag(option.code)
                                    }
                                }
                                .frame(width: 140)
                                .onChange(of: userSettings.shortcutKeyCode) { _ in
                                    applyShortcut()
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Modifiers")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(mutedColor)
                                HStack(spacing: 10) {
                                    modifierChip("Command")
                                    modifierChip("Shift")
                                    modifierChip("Option")
                                    modifierChip("Control")
                                }
                            }
                        }
                    }
                }
                
                // Prompt Shortcuts Section
                SettingSection(title: "Prompt Shortcuts", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(accentColor)
                            Text("Assign keyboard shortcuts to your custom prompts for quick access")
                                .font(.system(size: 13))
                                .foregroundColor(mutedColor)
                        }

                        Text("Tip: keep prompt shortcuts different from your default shortcut.")
                            .font(.system(size: 13))
                            .foregroundColor(mutedColor)
                        
                        if userSettings.customPrompts.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "keyboard.badge.exclamationmark")
                                    .font(.system(size: 20))
                                    .foregroundColor(mutedColor.opacity(0.5))
                                Text("Create custom prompts first to assign shortcuts")
                                    .font(.system(size: 12))
                                    .foregroundColor(mutedColor)
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(userSettings.customPrompts) { prompt in
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 14))
                                            .foregroundColor(mutedColor)
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(prompt.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(textColor)
                                            
                                            let shortcut = userSettings.promptShortcuts[prompt.id.uuidString]
                                            Text(shortcut != nil ? formatShortcut(shortcut!) : "No shortcut")
                                                .font(.system(size: 11, weight: shortcut != nil ? .semibold : .regular))
                                                .foregroundColor(shortcut != nil ? accentColor : mutedColor.opacity(0.5))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(shortcut != nil ? accentColor.opacity(0.1) : Color.clear)
                                                .cornerRadius(3)
                                        }
                                        
                                        Spacer()
                                        
                                        // Add/Edit button
                                        Button(action: {
                                            selectedPromptForShortcut = prompt
                                            if let existing = userSettings.promptShortcuts[prompt.id.uuidString] {
                                                editingShortcutKey = existing.keyCode
                                                editingShortcutModifiers = existing.modifiers
                                            } else {
                                                editingShortcutKey = 0
                                                editingShortcutModifiers = ["command"]
                                            }
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Text(userSettings.promptShortcuts[prompt.id.uuidString] != nil ? "Add / Edit" : "Add")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(accentColor)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(accentColor.opacity(0.45), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        // Clear button (if exists)
                                        if userSettings.promptShortcuts[prompt.id.uuidString] != nil {
                                            Button(action: {
                                                userSettings.promptShortcuts.removeValue(forKey: prompt.id.uuidString)
                                                applyShortcut()
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(mutedColor)
                                                    .frame(width: 26, height: 26)
                                                    .background(Color.gray.opacity(0.15))
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(creamBg)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(userSettings.promptShortcuts[prompt.id.uuidString] != nil ? accentColor.opacity(0.3) : (isDarkMode ? Color.white.opacity(0.1) : Color.gray.opacity(0.15)), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .background(creamBg)
        .onAppear {
            applyShortcut()
        }
        .sheet(item: $selectedPromptForShortcut) { prompt in
            PromptShortcutEditorSheet(
                prompt: prompt,
                keyCode: $editingShortcutKey,
                modifiers: $editingShortcutModifiers,
                keyOptions: keyOptions,
                creamBg: creamBg,
                accentColor: accentColor,
                textColor: textColor,
                mutedColor: mutedColor,
                onSave: {
                    let shortcut = PromptShortcut(
                        actionId: prompt.id.uuidString,
                        keyCode: editingShortcutKey,
                        modifiers: editingShortcutModifiers
                    )
                    userSettings.promptShortcuts[prompt.id.uuidString] = shortcut
                    applyShortcut()
                    selectedPromptForShortcut = nil
                },
                onCancel: {
                    selectedPromptForShortcut = nil
                }
            )
        }
    }

    @ViewBuilder
    private func modifierChip(_ modifier: String) -> some View {
        let isEnabled = userSettings.shortcutModifiers.contains(modifier.lowercased())
        Button {
            toggleModifier(modifier.lowercased())
        } label: {
            Text(modifier)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isEnabled ? .white : textColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isEnabled ? accentColor : creamBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private var isDarkMode: Bool {
        userSettings.theme == Theme.dark || (userSettings.theme == Theme.system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    private func toggleModifier(_ modifier: String) {
        var updated = userSettings.shortcutModifiers
        if let idx = updated.firstIndex(of: modifier) {
            updated.remove(at: idx)
        } else {
            updated.append(modifier)
        }

        if updated.isEmpty {
            updated = ["command"]
        }

        userSettings.shortcutModifiers = updated
        applyShortcut()
    }

    private func formatShortcut(_ shortcut: PromptShortcut) -> String {
        let modString = shortcut.modifiers.map {
            switch $0 {
            case "command": return "⌘"
            case "shift": return "⇧"
            case "option": return "⌥"
            case "control": return "⌃"
            default: return ""
            }
        }.joined()
        let keyLabel = keyOptions.first(where: { $0.code == shortcut.keyCode })?.label ?? "?"
        return "\(modString)\(keyLabel)"
    }

    private func applyShortcut() {
        shortcutManager?.updateShortcut(
            keyCode: userSettings.shortcutKeyCode,
            modifiers: userSettings.shortcutModifiers
        )
        shortcutManager?.updatePromptShortcuts(userSettings.promptShortcuts)
    }
}

// MARK: - Prompt Shortcut Editor Sheet
struct PromptShortcutEditorSheet: View {
    let prompt: CustomPrompt
    @Binding var keyCode: Int
    @Binding var modifiers: [String]
    let keyOptions: [(label: String, code: Int)]
    let creamBg: Color
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Shortcut for \"\(prompt.name)\"")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(textColor)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(mutedColor)
                }
                .buttonStyle(.plain)
            }
            
            Text("Choose a keyboard shortcut to quickly activate this prompt")
                .font(.system(size: 12))
                .foregroundColor(mutedColor)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(mutedColor)
                    Picker("Key", selection: $keyCode) {
                        ForEach(keyOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .frame(width: 140)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Modifiers")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(mutedColor)
                    HStack(spacing: 8) {
                        ForEach(["Command", "Shift", "Option", "Control"], id: \.self) { mod in
                            let isEnabled = modifiers.contains(mod.lowercased())
                            Button {
                                toggleModifier(mod.lowercased())
                            } label: {
                                Text(mod)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(isEnabled ? .white : textColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isEnabled ? accentColor : creamBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                                    )
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(mutedColor)
                
                Button("Save Shortcut") {
                    onSave()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(accentColor)
                .cornerRadius(8)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
    
    private func toggleModifier(_ modifier: String) {
        if let idx = modifiers.firstIndex(of: modifier) {
            modifiers.remove(at: idx)
        } else {
            modifiers.append(modifier)
        }
        if modifiers.isEmpty {
            modifiers = ["command"]
        }
    }
}

// MARK: - Usage View
struct UsageView: View {
    @ObservedObject var usageTracker: UsageTracker
    @ObservedObject var tokenManager = TokenManager.shared
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let creamBg: Color
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Usage")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                
                // Stats Cards Row
                HStack(spacing: 16) {
                    StatCard(
                        title: "Transformations",
                        value: "\(usageTracker.statistics.totalTransformations)",
                        icon: "wand.and.stars",
                        color: accentColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        cardBg: creamBg
                    )
                    
                    StatCard(
                        title: "Today Used",
                        value: "\(tokenManager.tokensUsedToday)/\(tokenManager.dailyLimit)",
                        icon: "arrow.counterclockwise",
                        color: tokenManager.tokensUsedToday >= tokenManager.dailyLimit ? Color.red : accentColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        cardBg: creamBg
                    )
                    
                    StatCard(
                        title: "Plan",
                        value: "Free",
                        icon: "crown.fill",
                        color: accentColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        cardBg: creamBg
                    )
                }
                
                // Activity Timeline
                SettingSection(title: "Activity Timeline", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 16) {
                        if usageTracker.entries.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 24))
                                    .foregroundColor(mutedColor.opacity(0.5))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("No activity yet")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(textColor)
                                    Text("Start using Draftlet to see your usage stats")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(mutedColor)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            // Daily activity breakdown
                            let dailyStats = calculateDailyStats()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(dailyStats.prefix(3), id: \.date) { day in
                                    HStack(spacing: 12) {
                                        Text(formatDate(day.date))
                                            .font(.system(size: 13))
                                            .foregroundColor(mutedColor)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(mutedColor.opacity(0.15))
                                                    .frame(height: 8)
                                                
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(accentColor)
                                                    .frame(width: geo.size.width * day.percentage, height: 8)
                                            }
                                        }
                                        .frame(height: 8)
                                        
                                        Text("\(day.count)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(textColor)
                                            .frame(width: 30, alignment: .trailing)
                                    }
                                    .frame(height: 24)
                                }
                            }
                        }
                    }
                }
                
                // Recent Activity
                if !usageTracker.entries.isEmpty {
                    SettingSection(title: "Recent Activity", accentColor: accentColor, cardBg: creamBg) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(usageTracker.entries.prefix(5)) { entry in
                                HStack(spacing: 12) {
                                    Image(systemName: entry.isSnippet ? "bookmark.fill" : "wand.and.stars")
                                        .font(.system(size: 12))
                                        .foregroundColor(entry.isSnippet ? accentColor : mutedColor)
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.action)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(textColor)
                                        
                                        Text(entry.timestamp, style: .relative)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(mutedColor)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                
                                if entry.id != usageTracker.entries.prefix(5).last?.id {
                                    Divider()
                                        .background(mutedColor.opacity(0.2))
                                }
                            }
                        }
                    }
                }
                
                // Usage Insights
                if usageTracker.statistics.firstUseDate != nil {
                    SettingSection(title: "Usage Insights", accentColor: accentColor, cardBg: creamBg) {
                        VStack(alignment: .leading, spacing: 12) {
                            InsightRow(
                                icon: "calendar",
                                title: "First Use",
                                value: usageTracker.statistics.firstUseDate != nil ? formatFullDate(usageTracker.statistics.firstUseDate!) : "-",
                                accentColor: accentColor,
                                textColor: textColor,
                                mutedColor: mutedColor
                            )
                            
                            InsightRow(
                                icon: "clock",
                                title: "Last Activity",
                                value: usageTracker.statistics.lastUseDate != nil ? formatFullDate(usageTracker.statistics.lastUseDate!) : "-",
                                accentColor: accentColor,
                                textColor: textColor,
                                mutedColor: mutedColor
                            )
                            
                            if usageTracker.statistics.totalTransformations > 0 {
                                let streak = calculateStreak()
                                InsightRow(
                                    icon: "flame.fill",
                                    title: "Current Streak",
                                    value: "\(streak) days",
                                    accentColor: accentColor,
                                    textColor: textColor,
                                    mutedColor: mutedColor
                                )
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(32)
        }
        .background(creamBg)
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func calculateStreak() -> Int {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: usageTracker.entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        var streak = 0
        var date = calendar.startOfDay(for: Date())
        
        while grouped.keys.contains(date) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previousDay
        }
        
        return streak
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func calculateDailyStats() -> [(date: Date, count: Int, percentage: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: usageTracker.entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        let maxCount = grouped.values.map { $0.count }.max() ?? 1
        
        let sortedDays = grouped.keys.sorted(by: >).prefix(3)
        
        return sortedDays.map { date in
            let count = grouped[date]?.count ?? 0
            return (date: date, count: count, percentage: Double(count) / Double(maxCount))
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let textColor: Color
    let mutedColor: Color
    let cardBg: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                
                Spacer()
            }
            
                VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(mutedColor)
                    .tracking(0.3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Insight Row
struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(accentColor)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(mutedColor)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
        }
    }
}

// MARK: - History View
struct HistoryView: View {
    @ObservedObject var usageTracker: UsageTracker
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let creamBg: Color
    let sidebarBg: Color
    let isDarkMode: Bool
    
    @State private var searchText = ""
    @State private var selectedEntry: UsageEntry?
    @State private var showingPrivacyInfo = false
    @State private var showingExportResult = false
    @State private var exportResultMessage = ""
    @State private var exportSuccess = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                // Header with search
                VStack(alignment: .leading, spacing: 12) {
                    Text("History")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(textColor)
                    
                    // Search bar with buttons
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(mutedColor)
                        
                        TextField("Search history...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 13))
                            .foregroundColor(textColor)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(mutedColor.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Clear search")
                        }
                        
                        Divider()
                            .frame(height: 16)
                        
                        // Info button
                        Button(action: { showingPrivacyInfo = true }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Privacy & Data Info")
                        
                        // Export button
                        Button(action: exportHistory) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Export History")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(creamBg)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(16)
                
                // Entries list
                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(mutedColor.opacity(0.4))
                        
                        Text(searchText.isEmpty ? "No history yet" : "No matches found")
                            .font(.system(size: 13))
                            .foregroundColor(mutedColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredEntries) { entry in
                                HistoryRow(
                                    entry: entry,
                                    isSelected: selectedEntry?.id == entry.id,
                                    accentColor: accentColor,
                                    textColor: textColor,
                                    mutedColor: mutedColor
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(creamBg)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .scrollIndicators(.hidden)
                }
            }
            .frame(width: 320)
            .background(sidebarBg)
            
            // Detail view
            if let entry = selectedEntry {
                HistoryDetailView(
                    entry: entry,
                    accentColor: accentColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    bgColor: creamBg,
                    cardBg: isDarkMode ? Color(NSColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1.0)) : Color.white,
                    isDarkMode: isDarkMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(creamBg)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(mutedColor.opacity(0.3))
                    
                    Text("Select an entry")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(mutedColor)
                    
                    Text("Choose an item from the list to view details")
                        .font(.system(size: 13))
                        .foregroundColor(mutedColor.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(creamBg)
            }
        }
        .alert("Privacy & Data Storage", isPresented: $showingPrivacyInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your history is stored locally on your device only. We do not upload or store your text on any server. All data remains private and secure on your Mac.")
        }
        .alert(exportSuccess ? "Export Successful" : "Export Failed", isPresented: $showingExportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportResultMessage)
        }
    }
    
    private var filteredEntries: [UsageEntry] {
        if searchText.isEmpty {
            return usageTracker.entries
        }
        return usageTracker.search(query: searchText)
    }
    
    private func exportHistory() {
        guard !usageTracker.entries.isEmpty else {
            exportSuccess = false
            exportResultMessage = "No history to export. Use the app first to create some entries."
            showingExportResult = true
            return
        }
        
        // Create simplified export entries without unwanted fields
        struct SimpleExportEntry: Codable {
            let timestamp: Date
            let action: String
            let originalText: String
            let rewrittenText: String
        }
        
        let simpleEntries = usageTracker.entries.map { entry in
            SimpleExportEntry(
                timestamp: entry.timestamp,
                action: entry.action,
                originalText: entry.originalText,
                rewrittenText: entry.rewrittenText
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(simpleEntries)
            
            let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard let downloadsURL = downloadsPath else {
                exportSuccess = false
                exportResultMessage = "Could not access Downloads folder"
                showingExportResult = true
                return
            }
            
            let fileURL = downloadsURL.appendingPathComponent("AIWritingAssistant_History.json")
            try data.write(to: fileURL)
            
            exportSuccess = true
            exportResultMessage = "History exported to Downloads folder as 'AIWritingAssistant_History.json' with \(simpleEntries.count) entries."
            showingExportResult = true
        } catch {
            exportSuccess = false
            exportResultMessage = "Export failed: \(error.localizedDescription)"
            showingExportResult = true
        }
    }
}

// MARK: - System Prompt View
struct SystemPromptView: View {
    @ObservedObject var userSettings: UserSettings
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let creamBg: Color
    
    @State private var showingAddPrompt = false
    @State private var editingPrompt: CustomPrompt? = nil
    @State private var newPromptName = ""
    @State private var newPromptContent = ""
    @State private var showingSmartPromptInfo = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("System Prompt")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(textColor)
                
                // Smart Prompt Section
                SettingSection(title: "Smart Prompt", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16))
                                .foregroundColor(accentColor)
                            
                            Text("Enable Smart Prompt")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(textColor)
                            
                            Spacer()
                            
                            // Info button
                            Button(action: { showingSmartPromptInfo.toggle() }) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("How Smart Prompt works")
                            
                            Toggle("", isOn: $userSettings.useSmartPrompt)
                                .toggleStyle(SwitchToggleStyle(tint: accentColor))
                                .labelsHidden()
                        }
                        
                        if showingSmartPromptInfo {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("How to use Smart Prompt:")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(textColor)
                                
                                Text("Add instructions in brackets at the end of your text:")
                                    .font(.system(size: 11))
                                    .foregroundColor(mutedColor)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• \"Hello world (make it shorter)\"")
                                    Text("• \"Write a function (as Python code)\"")
                                    Text("• \"Meeting notes (summarize briefly)\"")
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(accentColor)
                                .padding(8)
                                .background(accentColor.opacity(0.08))
                                .cornerRadius(6)
                            }
                            .padding(.top, 8)
                        }
                        
                        if userSettings.useSmartPrompt {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundColor(accentColor)
                                Text("Smart Prompt active - add (instructions) at end of text")
                                    .font(.system(size: 11))
                                    .foregroundColor(mutedColor)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                
                // Default Actions Section
                SettingSection(title: "Quick Actions", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select your default action or use custom prompts below")
                            .font(.system(size: 13))
                            .foregroundColor(mutedColor)
                            .padding(.bottom, 4)
                        
                        ForEach(AIAction.allCases.filter { $0 != .custom && $0 != .smartPrompt }, id: \.self) { action in
                            ImprovedActionOption(
                                action: action,
                                isSelected: userSettings.defaultAction == action && !userSettings.useSmartPrompt && userSettings.selectedCustomPromptId == nil,
                                accentColor: accentColor,
                                textColor: textColor,
                                mutedColor: mutedColor,
                                cardBg: creamBg
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    userSettings.defaultAction = action
                                    userSettings.useSmartPrompt = false
                                    userSettings.selectedCustomPromptId = nil
                                }
                            }
                        }
                    }
                }
                
                // Custom Prompts Section
                SettingSection(title: "Custom Prompts", accentColor: accentColor, cardBg: creamBg) {
                    VStack(alignment: .leading, spacing: 12) {
                        if userSettings.customPrompts.isEmpty {
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 24))
                                    .foregroundColor(mutedColor.opacity(0.5))
                                Text("No custom prompts yet")
                                    .font(.system(size: 13))
                                    .foregroundColor(mutedColor)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            ForEach(userSettings.customPrompts) { prompt in
                                CustomPromptRow(
                                    prompt: prompt,
                                    isSelected: userSettings.selectedCustomPromptId == prompt.id && !userSettings.useSmartPrompt,
                                    accentColor: accentColor,
                                    textColor: textColor,
                                    mutedColor: mutedColor,
                                    cardBg: creamBg,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            userSettings.selectedCustomPromptId = prompt.id
                                            userSettings.useSmartPrompt = false
                                            userSettings.defaultAction = .custom
                                        }
                                    },
                                    onEdit: {
                                        editingPrompt = prompt
                                        newPromptName = prompt.name
                                        newPromptContent = prompt.content
                                    },
                                    onDelete: {
                                        deletePrompt(prompt)
                                    }
                                )
                            }
                        }
                        
                        Button(action: { showingAddPrompt = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("Add Custom Prompt")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .background(creamBg)
        .sheet(isPresented: $showingAddPrompt) {
            PromptEditorSheet(
                isPresented: $showingAddPrompt,
                promptName: $newPromptName,
                promptContent: $newPromptContent,
                isEditing: false,
                accentColor: accentColor,
                textColor: textColor,
                mutedColor: mutedColor,
                onSave: { name, content in
                    let newPrompt = CustomPrompt(name: name, content: content)
                    userSettings.customPrompts.append(newPrompt)
                    userSettings.selectedCustomPromptId = newPrompt.id
                    userSettings.useSmartPrompt = false
                    userSettings.defaultAction = .custom
                    newPromptName = ""
                    newPromptContent = ""
                }
            )
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditorSheet(
                isPresented: Binding(
                    get: { editingPrompt != nil },
                    set: { if !$0 { editingPrompt = nil } }
                ),
                promptName: $newPromptName,
                promptContent: $newPromptContent,
                isEditing: true,
                accentColor: accentColor,
                textColor: textColor,
                mutedColor: mutedColor,
                onSave: { name, content in
                    if let index = userSettings.customPrompts.firstIndex(where: { $0.id == prompt.id }) {
                        userSettings.customPrompts[index].name = name
                        userSettings.customPrompts[index].content = content
                    }
                    editingPrompt = nil
                    newPromptName = ""
                    newPromptContent = ""
                }
            )
        }
    }
    
    private func deletePrompt(_ prompt: CustomPrompt) {
        userSettings.customPrompts.removeAll { $0.id == prompt.id }
        if userSettings.selectedCustomPromptId == prompt.id {
            userSettings.selectedCustomPromptId = nil
            userSettings.defaultAction = .fixGrammar
        }
    }
}

// MARK: - Improved Action Option
struct ImprovedActionOption: View {
    let action: AIAction
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let cardBg: Color
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Radio button style
            ZStack {
                Circle()
                    .stroke(isSelected ? accentColor : mutedColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                if isSelected {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                }
            }
            
            Image(systemName: action.iconName)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? accentColor : mutedColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? textColor : mutedColor)
                
                Text(action.description)
                    .font(.system(size: 11))
                    .foregroundColor(mutedColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
            }
        }
        .padding(12)
        .background(isSelected ? accentColor.opacity(0.06) : cardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? accentColor.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Custom Prompt Row
struct CustomPromptRow: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let cardBg: Color
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Radio button
            ZStack {
                Circle()
                    .stroke(isSelected ? accentColor : mutedColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 18, height: 18)
                
                if isSelected {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 9, height: 9)
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(prompt.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? textColor : mutedColor)
                
                Text(prompt.content.prefix(40) + (prompt.content.count > 40 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(mutedColor.opacity(0.8))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Edit button - NOT inside the selection tap area
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(mutedColor)
                    .frame(width: 26, height: 26)
                    .background(cardBg)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Edit prompt")
            
            // Delete button - NOT inside the selection tap area
            Button(action: { showingDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Color.red.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(cardBg)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete prompt")
            .alert("Delete Prompt?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: onDelete)
            } message: {
                Text("Are you sure you want to delete \"\(prompt.name)\"?")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? accentColor.opacity(0.06) : cardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? accentColor.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Prompt Editor Sheet
struct PromptEditorSheet: View {
    @Binding var isPresented: Bool
    @Binding var promptName: String
    @Binding var promptContent: String
    let isEditing: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let onSave: (String, String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(isEditing ? "Edit Prompt" : "New Custom Prompt")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textColor)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(mutedColor)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(mutedColor)
                TextField("e.g., Professional Email", text: $promptName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt Instructions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(mutedColor)
                TextEditor(text: $promptContent)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .padding(4)
                    .background(creamBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isDarkMode ? Color.white.opacity(0.1) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .foregroundColor(mutedColor)
                
                Button("Save") {
                    if !promptName.isEmpty && !promptContent.isEmpty {
                        onSave(promptName, promptContent)
                        isPresented = false
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(promptName.isEmpty || promptContent.isEmpty ? mutedColor.opacity(0.4) : accentColor)
                .cornerRadius(8)
                .disabled(promptName.isEmpty || promptContent.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
    
    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    private var creamBg: Color {
        isDarkMode ? Color(NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)) : Color.white
    }
}

// MARK: - Action Option (Legacy - for backwards compatibility)
struct ActionOption: View {
    let action: AIAction
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let onSelect: () -> Void
    
    var body: some View {
        ImprovedActionOption(
            action: action,
            isSelected: isSelected,
            accentColor: accentColor,
            textColor: textColor,
            mutedColor: mutedColor,
            cardBg: Color.white,
            onSelect: onSelect
        )
    }
}

// MARK: - History Row
struct HistoryRow: View {
    let entry: UsageEntry
    let isSelected: Bool
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isSnippet ? "bookmark.fill" : "text.quote")
                .font(.system(size: 12))
                .foregroundColor(entry.isSnippet ? accentColor : mutedColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textColor)
                
                Text(entry.originalText.prefix(25) + (entry.originalText.count > 25 ? "..." : ""))
                    .font(.system(size: 11))
                    .foregroundColor(mutedColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(entry.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundColor(mutedColor.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - History Detail View
struct HistoryDetailView: View {
    let entry: UsageEntry
    let accentColor: Color
    let textColor: Color
    let mutedColor: Color
    let bgColor: Color
    let cardBg: Color
    let isDarkMode: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.action)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(textColor)
                        
                        Text(entry.timestamp, format: .dateTime)
                            .font(.system(size: 12))
                            .foregroundColor(mutedColor)
                    }
                    
                    Spacer()
                    
                    if entry.isSnippet {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10))
                            Text("Saved")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(mutedColor)
                        .textCase(.uppercase)
                    
                    Text(entry.originalText)
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isDarkMode ? Color.white.opacity(0.1) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rewritten")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                        .textCase(.uppercase)
                    
                    Text(entry.rewrittenText)
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(accentColor.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(accentColor.opacity(0.2), lineWidth: 1)
                        )
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(bgColor)
    }
}
