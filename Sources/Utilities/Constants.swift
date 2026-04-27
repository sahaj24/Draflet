import Foundation

// MARK: - App Constants
/// Global app constants and configuration
enum AppConstants {
    /// App version
    static let version = "1.0.0"
    
    /// Build number
    static let build = "1"
    
    /// Default global shortcut
    static let defaultShortcutKeyCode = 0 // 'A'
    static let defaultShortcutModifiers = ["command", "shift"]
    
    /// Window sizes
    static let floatingWindowWidth: CGFloat = 320
    static let floatingWindowHeight: CGFloat = 400
    static let settingsWindowWidth: CGFloat = 700
    static let settingsWindowHeight: CGFloat = 500
    static let historyWindowWidth: CGFloat = 900
    static let historyWindowHeight: CGFloat = 600
}

// MARK: - UserDefaultKeys
/// Keys for UserDefaults storage
enum UserDefaultsKeys {
    static let settings = "AIWritingAssistantSettings"
    static let usageEntries = "AIWritingAssistantUsageEntries"
    static let usageStatistics = "AIWritingAssistantUsageStatistics"
}
