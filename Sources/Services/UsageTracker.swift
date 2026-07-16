import Foundation
import Combine

// MARK: - UsageEntry
/// Represents a single usage of the Draflet
struct UsageEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let action: String
    let originalText: String
    let rewrittenText: String
    let model: String
    let tokensIn: Int
    let tokensOut: Int
    var isSnippet: Bool
    var snippetName: String?
    
    static func == (lhs: UsageEntry, rhs: UsageEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: String,
        originalText: String,
        rewrittenText: String,
        model: String,
        tokensIn: Int = 0,
        tokensOut: Int = 0,
        isSnippet: Bool = false,
        snippetName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.model = model
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.isSnippet = isSnippet
        self.snippetName = snippetName
    }
}

// MARK: - UsageStatistics
/// Aggregated usage statistics for the app
struct UsageStatistics: Codable {
    var totalTransformations: Int
    var totalSnippets: Int
    var totalTokensUsed: Int
    var firstUseDate: Date?
    var lastUseDate: Date?
    
    init() {
        self.totalTransformations = 0
        self.totalSnippets = 0
        self.totalTokensUsed = 0
        self.firstUseDate = nil
        self.lastUseDate = nil
    }
}

// MARK: - UsageTracker
/// Tracks usage history, snippets, and statistics
class UsageTracker: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var entries: [UsageEntry] = []
    @Published var statistics: UsageStatistics = UsageStatistics()
    
    // MARK: - Private Properties
    
    private let entriesKey = "AIWritingAssistantUsageEntries"
    private let statisticsKey = "AIWritingAssistantUsageStatistics"
    private let maxStoredEntries = 100 // Keep only last 100 entries
    private let freeTierDailyLimit = 20
    
    // MARK: - Initialization
    
    init() {
        loadData()
    }
    
    // MARK: - Public Methods
    
    /// Records a new usage entry
    func recordUsage(
        action: AIAction,
        originalText: String,
        rewrittenText: String,
        model: String,
        tokensIn: Int = 0,
        tokensOut: Int = 0
    ) {
        let entry = UsageEntry(
            action: action.displayName,
            originalText: originalText,
            rewrittenText: rewrittenText,
            model: model,
            tokensIn: tokensIn,
            tokensOut: tokensOut
        )
        
        entries.insert(entry, at: 0)
        
        // Limit entries count
        if entries.count > maxStoredEntries {
            entries = Array(entries.prefix(maxStoredEntries))
        }
        
        // Update statistics
        statistics.totalTransformations += 1
        statistics.totalTokensUsed += (tokensIn + tokensOut)
        statistics.lastUseDate = Date()
        if statistics.firstUseDate == nil {
            statistics.firstUseDate = Date()
        }
        
        saveData()
    }
    
    /// Saves an entry as a named snippet
    func saveAsSnippet(_ entry: UsageEntry, name: String) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].isSnippet = true
            entries[index].snippetName = name
            statistics.totalSnippets += 1
            saveData()
        }
    }
    
    /// Creates a new snippet from current text
    func createSnippet(name: String, originalText: String, rewrittenText: String, action: String, model: String) {
        let entry = UsageEntry(
            action: action,
            originalText: originalText,
            rewrittenText: rewrittenText,
            model: model,
            isSnippet: true,
            snippetName: name
        )
        
        entries.insert(entry, at: 0)
        statistics.totalSnippets += 1
        saveData()
    }
    
    /// Deletes an entry
    func deleteEntry(_ entry: UsageEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            if entries[index].isSnippet {
                statistics.totalSnippets -= 1
            }
            statistics.totalTransformations -= 1
            entries.remove(at: index)
            saveData()
        }
    }
    
    /// Returns only snippet entries
    func snippets() -> [UsageEntry] {
        return entries.filter { $0.isSnippet }
    }
    
    /// Returns the number of uses today
    var todayUsageCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return entries.filter { calendar.startOfDay(for: $0.timestamp) == today }.count
    }
    
    /// Checks if user has exceeded the free tier daily limit (20 uses/day)
    var hasExceededDailyLimit: Bool {
        return todayUsageCount >= freeTierDailyLimit
    }
    
    /// Returns remaining uses for today
    var remainingUsesToday: Int {
        return max(0, freeTierDailyLimit - todayUsageCount)
    }
    
    /// Searches entries by text content
    func search(query: String) -> [UsageEntry] {
        guard !query.isEmpty else { return entries }
        
        let lowercasedQuery = query.lowercased()
        return entries.filter { entry in
            entry.originalText.lowercased().contains(lowercasedQuery) ||
            entry.rewrittenText.lowercased().contains(lowercasedQuery) ||
            entry.action.lowercased().contains(lowercasedQuery) ||
            (entry.snippetName?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }
    
    /// Clears all history
    func clearHistory() {
        entries.removeAll()
        statistics = UsageStatistics()
        saveData()
    }
    
    /// Exports history to JSON
    func exportToJSON() -> Data? {
        struct ExportData: Codable {
            let exportDate: Date
            let statistics: UsageStatistics
            let entries: [UsageEntry]
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(
            ExportData(
                exportDate: Date(),
                statistics: statistics,
                entries: entries
            )
        )
    }
    
    // MARK: - Private Methods
    
    /// Saves all data to UserDefaults
    private func saveData() {
        if let entriesData = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
        
        if let statsData = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(statsData, forKey: statisticsKey)
        }
    }
    
    /// Loads all data from UserDefaults
    private func loadData() {
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey),
           let loadedEntries = try? JSONDecoder().decode([UsageEntry].self, from: entriesData) {
            entries = loadedEntries
        }
        
        if let statsData = UserDefaults.standard.data(forKey: statisticsKey),
           let loadedStats = try? JSONDecoder().decode(UsageStatistics.self, from: statsData) {
            statistics = loadedStats
        }
    }
}
