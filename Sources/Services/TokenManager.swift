import Foundation
import AppKit

// MARK: - Token Manager
/// Manages user tokens for AI usage tracking
class TokenManager: ObservableObject {
    
    static let shared = TokenManager()
    
    @Published var tokensRemaining: Int = 0
    @Published var tokensUsedToday: Int = 0
    @Published var dailyLimit: Int = 20
    @Published var plan: String = "free"
    @Published var lastResetAt: Date?
    @Published var isLoading: Bool = false
    
    private let supabaseURL = "https://kgypcdyiszmsdvxzkocq.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtneXBjZHlpc3ptc2R2eHprb2NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5MDk1MDIsImV4cCI6MjA4OTQ4NTUwMn0.BA8YRs2F0IoKPs9Q0aklsJjtzkPx464kodlVcuzY6Jw"
    private var refreshTimer: Timer?
    
    private init() {
        // Start periodic refresh
        startTokenRefreshTimer()
    }
    
    // MARK: - Token Fetching
    
    /// Fetch current token balance from Supabase
    func fetchTokens() async {
        guard let session = AuthManager.shared.currentUser else {
            await MainActor.run {
                self.tokensRemaining = 0
                self.tokensUsedToday = 0
            }
            return
        }
        
        let accessToken = session.accessToken
        
        await MainActor.run { isLoading = true }
        
        do {
            let url = URL(string: "\(supabaseURL)/rest/v1/user_tokens?select=*&user_id=eq.\(session.userId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    print("fetchTokens failed status=\(httpResponse.statusCode) body=\(body)")
                }
                await MainActor.run { isLoading = false }
                return
            }
            
            if let tokens = try? JSONDecoder().decode([UserTokenRecord].self, from: data),
               let token = tokens.first {
                await MainActor.run {
                    self.tokensRemaining = token.tokens_remaining
                    self.tokensUsedToday = token.tokens_used_today
                    self.dailyLimit = token.daily_limit
                    self.plan = token.plan
                    self.lastResetAt = ISO8601DateFormatter().date(from: token.last_reset_at)
                    self.isLoading = false
                }
            } else {
                // No record found, create one
                await createInitialTokenRecord(
                    accessToken: accessToken,
                    userId: session.userId,
                    email: session.email,
                    fullName: session.displayName
                )
            }
        } catch {
            print("Failed to fetch tokens: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize tokens for new user - creates entry in DB if missing
    func initializeTokensForNewUser() async {
        await fetchTokens()
    }
    
    /// Create initial token record for new users
    private func createInitialTokenRecord(accessToken: String, userId: String, email: String?, fullName: String?) async {
        let url = URL(string: "\(supabaseURL)/rest/v1/user_tokens")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        var body: [String: Any] = [
            "user_id": userId,
            "tokens_remaining": 20,
            "daily_limit": 20,
            "plan": "free"
        ]
        if let email {
            body["email"] = email
        }
        if let fullName {
            body["full_name"] = fullName
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let tokens = try? JSONDecoder().decode([UserTokenRecord].self, from: data),
               let token = tokens.first {
                await MainActor.run {
                    self.tokensRemaining = token.tokens_remaining
                    self.tokensUsedToday = token.tokens_used_today
                    self.dailyLimit = token.daily_limit
                    self.plan = token.plan
                }
            }
        } catch {
            print("Failed to create token record: \(error)")
        }
    }
    
    // MARK: - Token Consumption
    
    /// Consume tokens for AI usage - always fetches from DB first
    /// - Returns: (success, remainingTokens, errorMessage)
    func consumeTokens(amount: Int = 1) async -> (Bool, Int, String?) {
        guard let session = AuthManager.shared.currentUser else {
            return (false, 0, "Not authenticated")
        }

        // ALWAYS fetch fresh tokens from DB first (no local caching)
        await fetchTokens()

        let accessToken = session.accessToken

        do {
            let url = URL(string: "\(supabaseURL)/rest/v1/rpc/consume_tokens")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let body: [String: Any] = [
                "p_user_id": session.userId,
                "p_amount": amount
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Token consumption failed: \(errorBody)")
                return (false, tokensRemaining, "Failed to consume tokens")
            }

            // Parse RPC response and support both object and single-row array shapes.
            if let result = try? JSONDecoder().decode(TokenConsumptionResult.self, from: data) {
                await MainActor.run {
                    self.tokensRemaining = result.tokens_remaining
                }
                // Refresh to keep DB-backed counters in sync in UI.
                await fetchTokens()
                return (result.success, result.tokens_remaining, result.error_message)
            }

            if let results = try? JSONDecoder().decode([TokenConsumptionResult].self, from: data),
               let result = results.first {
                await MainActor.run {
                    self.tokensRemaining = result.tokens_remaining
                }
                await fetchTokens()
                return (result.success, result.tokens_remaining, result.error_message)
            }

            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("Invalid consume_tokens response: \(raw)")
            return (false, tokensRemaining, "Invalid response from server")
            
        } catch {
            print("Error consuming tokens: \(error)")
            return (false, tokensRemaining, error.localizedDescription)
        }
    }
    
    // MARK: - Admin Functions
    
    /// Manually set tokens (for admin use or payment processing)
    func adminSetTokens(amount: Int, plan: String? = nil) async -> Bool {
        guard let session = AuthManager.shared.currentUser else {
            return false
        }
        
        let accessToken = session.accessToken
        
        do {
            let url = URL(string: "\(supabaseURL)/rest/v1/rpc/admin_set_tokens")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = [
                "p_user_id": session.userId,
                "p_tokens": amount
            ]
            if let plan = plan {
                body["p_plan"] = plan
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                await fetchTokens()
                return true
            }
            return false
        } catch {
            print("Failed to set tokens: \(error)")
            return false
        }
    }
    
    // MARK: - Helpers
    
    /// Check if user has enough tokens without consuming
    func hasEnoughTokens(amount: Int = 1) -> Bool {
        return tokensRemaining >= amount
    }
    
    /// Check if user can perform AI action
    var canUseAI: Bool {
        tokensRemaining > 0
    }
    
    /// Get token status text for UI
    var tokenStatusText: String {
        "\(tokensRemaining)/\(dailyLimit)"
    }
    
    /// Get color based on token level
    var tokenStatusColor: NSColor {
        if tokensRemaining == 0 {
            return NSColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1.0) // Red
        } else if tokensRemaining <= 5 {
            return NSColor(red: 0.95, green: 0.65, blue: 0.20, alpha: 1.0) // Orange
        } else {
            return NSColor(red: 0.25, green: 0.65, blue: 0.35, alpha: 1.0) // Green
        }
    }
    
    /// Start timer to refresh tokens periodically
    private func startTokenRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchTokens()
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Data Models

struct UserTokenRecord: Codable {
    let id: String
    let user_id: String
    let tokens_remaining: Int
    let tokens_used_today: Int
    let daily_limit: Int
    let plan: String
    let last_reset_at: String
    let last_updated_at: String
    let created_at: String
}

struct TokenConsumptionResult: Codable {
    let success: Bool
    let tokens_remaining: Int
    let error_message: String?
}
