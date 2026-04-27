import Foundation
import Combine

// MARK: - AIProvider
/// Supported AI API providers
enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic = "anthropic"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        }
    }
}

// MARK: - SettingsManager
/// Manages application settings and user preferences
/// Persists settings using UserDefaults
class SettingsManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var apiKey: String {
        didSet { saveToUserDefaults() }
    }
    
    @Published var selectedProvider: AIProvider {
        didSet { 
            updateDefaultModel()
            saveToUserDefaults() 
        }
    }
    
    @Published var selectedModel: String {
        didSet { saveToUserDefaults() }
    }
    
    @Published var shortcutKeyCode: Int {
        didSet { saveToUserDefaults() }
    }
    
    @Published var shortcutModifiers: [String] {
        didSet { saveToUserDefaults() }
    }
    
    @Published var startAtLogin: Bool {
        didSet { saveToUserDefaults() }
    }
    
    @Published var soundEffects: Bool {
        didSet { saveToUserDefaults() }
    }
    
    @Published var theme: Theme {
        didSet { saveToUserDefaults() }
    }
    
    @Published var isAdmin: Bool {
        didSet { saveToUserDefaults() }
    }
    
    // MARK: - Constants
    
    private let userDefaultsKey = "AIWritingAssistantSettings"
    
    // MARK: - Initialization
    
    init() {
        // Set default values
        self.apiKey = ""
        self.selectedProvider = .openAI
        self.selectedModel = "gpt-4o-mini"
        self.shortcutKeyCode = 0 // 'A'
        self.shortcutModifiers = ["command", "shift"]
        self.startAtLogin = true
        self.soundEffects = false
        self.theme = .system
        self.isAdmin = false
        
        // Load saved settings
        loadFromUserDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Returns available models for the selected provider
    func availableModels() -> [String] {
        switch selectedProvider {
        case .openAI:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-3.5-turbo"
            ]
        case .anthropic:
            return [
                "claude-3-5-sonnet-20241022",
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307"
            ]
        }
    }
    
    /// Returns display name for a model
    func displayName(for model: String) -> String {
        let displayNames: [String: String] = [
            "gpt-4o": "GPT-4o (Latest)",
            "gpt-4o-mini": "GPT-4o Mini (Fast)",
            "gpt-4-turbo": "GPT-4 Turbo",
            "gpt-3.5-turbo": "GPT-3.5 Turbo",
            "claude-3-5-sonnet-20241022": "Claude 3.5 Sonnet (Best)",
            "claude-3-opus-20240229": "Claude 3 Opus (Powerful)",
            "claude-3-sonnet-20240229": "Claude 3 Sonnet",
            "claude-3-haiku-20240307": "Claude 3 Haiku (Fast)"
        ]
        return displayNames[model] ?? model
    }
    
    /// Resets all settings to defaults
    func resetToDefaults() {
        apiKey = ""
        selectedProvider = .openAI
        selectedModel = "gpt-4o-mini"
        shortcutKeyCode = 0
        shortcutModifiers = ["command", "shift"]
        startAtLogin = true
        soundEffects = false
        theme = .system
        isAdmin = false
        saveToUserDefaults()
    }
    
    // MARK: - Private Methods
    
    /// Updates the selected model when provider changes
    private func updateDefaultModel() {
        switch selectedProvider {
        case .openAI:
            selectedModel = "gpt-4o-mini"
        case .anthropic:
            selectedModel = "claude-3-5-sonnet-20241022"
        }
    }
    
    /// Saves current settings to UserDefaults
    private func saveToUserDefaults() {
        let settings: [String: Any] = [
            "apiKey": apiKey,
            "selectedProvider": selectedProvider.rawValue,
            "selectedModel": selectedModel,
            "shortcutKeyCode": shortcutKeyCode,
            "shortcutModifiers": shortcutModifiers,
            "startAtLogin": startAtLogin,
            "soundEffects": soundEffects,
            "theme": theme.rawValue,
            "isAdmin": isAdmin
        ]
        UserDefaults.standard.set(settings, forKey: userDefaultsKey)
    }
    
    /// Loads settings from UserDefaults
    private func loadFromUserDefaults() {
        guard let settings = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else {
            return
        }
        
        if let apiKey = settings["apiKey"] as? String {
            self.apiKey = apiKey
        }
        
        if let providerString = settings["selectedProvider"] as? String,
           let provider = AIProvider(rawValue: providerString) {
            self.selectedProvider = provider
        }
        
        if let model = settings["selectedModel"] as? String {
            self.selectedModel = model
        }
        
        if let keyCode = settings["shortcutKeyCode"] as? Int {
            self.shortcutKeyCode = keyCode
        }
        
        if let modifiers = settings["shortcutModifiers"] as? [String] {
            self.shortcutModifiers = modifiers
        }
        
        if let startAtLogin = settings["startAtLogin"] as? Bool {
            self.startAtLogin = startAtLogin
        }
        
        if let soundEffects = settings["soundEffects"] as? Bool {
            self.soundEffects = soundEffects
        }
        
        if let themeString = settings["theme"] as? String,
           let theme = Theme(rawValue: themeString) {
            self.theme = theme
        }
        
        if let admin = settings["isAdmin"] as? Bool {
            self.isAdmin = admin
        }
    }
}

// MARK: - Theme
enum Theme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}
