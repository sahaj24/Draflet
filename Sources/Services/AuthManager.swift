import Foundation
import Cocoa
import AuthenticationServices

// MARK: - Auth Error
enum AuthError: Error {
    case invalidURL
    case authenticationFailed(String)
    case tokenExpired
    case noSession
    case networkError
    case invalidResponse
    case unknown
}

// MARK: - User Session
struct UserSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let plan: String
    
    var isValid: Bool {
        return Date() < expiresAt
    }
}

// MARK: - Auth Manager
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: UserSession?
    @Published var isLoading = false
    
    private let supabaseURL = "https://kgypcdyiszmsdvxzkocq.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtneXBjZHlpc3ptc2R2eHprb2NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5MDk1MDIsImV4cCI6MjA4OTQ4NTUwMn0.BA8YRs2F0IoKPs9Q0aklsJjtzkPx464kodlVcuzY6Jw"
    
    private let sessionKey = "AIWritingAssistantUserSession"
    private var webAuthSession: ASWebAuthenticationSession?
    
    private init() {
        loadSession()
    }
    
    // MARK: - Public Methods
    
    /// Starts Google OAuth login flow
    func signInWithGoogle(presentationContext: ASWebAuthenticationPresentationContextProviding, completion: @escaping (Result<UserSession, AuthError>) -> Void) {
        isLoading = true
        
        guard let authURL = buildGoogleAuthURL() else {
            isLoading = false
            completion(.failure(.invalidURL))
            return
        }
        
        // Create web authentication session
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "aiwriting"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    completion(.failure(.authenticationFailed(error.localizedDescription)))
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    completion(.failure(.noSession))
                    return
                }
                
                // Exchange the code for tokens
                self.exchangeCodeForTokens(callbackURL: callbackURL, completion: completion)
            }
        }
        
        session.presentationContextProvider = presentationContext
        
        self.webAuthSession = session
        session.start()
    }
    
    /// Sign out the current user
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
        NotificationCenter.default.post(name: NSNotification.Name("AuthStateChanged"), object: nil)
        
        // Also sign out from Supabase
        Task {
            await performSignOut()
        }
    }
    
    /// Refresh the access token if needed
    func refreshTokenIfNeeded() async -> String? {
        guard let session = currentUser else { return nil }
        
        // If token is still valid, return it
        if session.isValid {
            return session.accessToken
        }
        
        // Otherwise, refresh the token
        return await performTokenRefresh()
    }
    
    /// Get valid access token for API calls
    func getValidToken() async -> String? {
        return await refreshTokenIfNeeded()
    }
    
    // MARK: - Private Methods
    
    private func buildGoogleAuthURL() -> URL? {
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        
        let queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: "aiwriting://callback"),
            URLQueryItem(name: "scopes", value: "openid email profile")
        ]
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    private func exchangeCodeForTokens(callbackURL: URL, completion: @escaping (Result<UserSession, AuthError>) -> Void) {
        // Extract the code from the callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            completion(.failure(.authenticationFailed("No authorization code found")))
            return
        }
        
        // Exchange code for session
        Task {
            do {
                let session = try await self.exchangeCode(code: code)
                
                // Initialize tokens in database for new user
                await TokenManager.shared.initializeTokensForNewUser()
                
                DispatchQueue.main.async {
                    self.currentUser = session
                    self.isAuthenticated = true
                    self.saveSession(session)
                    NotificationCenter.default.post(name: NSNotification.Name("AuthStateChanged"), object: nil)
                    completion(.success(session))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.authenticationFailed(error.localizedDescription)))
                }
            }
        }
    }
    
    private func exchangeCode(code: String) async throws -> UserSession {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=pkce") else {
            throw AuthError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "auth_code": code,
            "code_verifier": generateCodeVerifier()
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(supabaseAnonKey)", forHTTPHeaderField: "apikey")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.authenticationFailed("Failed to exchange code")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String else {
            throw AuthError.invalidResponse
        }
        
        let email = user["email"] as? String
        let userMetadata = user["user_metadata"] as? [String: Any]
        let displayName = userMetadata?["full_name"] as? String ?? userMetadata?["name"] as? String
        let avatarUrl = userMetadata?["avatar_url"] as? String ?? userMetadata?["picture"] as? String
        
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        // Get user's plan from profiles table
        let plan = await fetchUserPlan(userId: userId)
        
        return UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            plan: plan
        )
    }
    
    private func performTokenRefresh() async -> String? {
        guard let refreshToken = currentUser?.refreshToken else { return nil }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            return nil
        }
        
        let requestBody: [String: Any] = [
            "refresh_token": refreshToken
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("\(supabaseAnonKey)", forHTTPHeaderField: "apikey")
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int,
                  let newRefreshToken = json["refresh_token"] as? String else {
                return nil
            }
            
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            
            // Update current session
            if var session = currentUser {
                session = UserSession(
                    accessToken: accessToken,
                    refreshToken: newRefreshToken,
                    expiresAt: expiresAt,
                    userId: session.userId,
                    email: session.email,
                    displayName: session.displayName,
                    avatarUrl: session.avatarUrl,
                    plan: session.plan
                )
                currentUser = session
                saveSession(session)
                return accessToken
            }
            
            return nil
        } catch {
            print("Token refresh failed: \(error)")
            return nil
        }
    }
    
    private func performSignOut() async {
        guard let accessToken = currentUser?.accessToken else { return }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/logout") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("\(supabaseAnonKey)", forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        _ = try? await URLSession.shared.data(for: request)
    }
    
    private func fetchUserPlan(userId: String) async -> String {
        // Default to free
        var plan = "free"
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=plan") else {
            return plan
        }
        
        var request = URLRequest(url: url)
        request.setValue("\(supabaseAnonKey)", forHTTPHeaderField: "apikey")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return plan
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let profile = json.first,
               let userPlan = profile["plan"] as? String {
                plan = userPlan
            }
        } catch {
            print("Failed to fetch user plan: \(error)")
        }
        
        return plan
    }
    
    private func loadSession() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(UserSession.self, from: data) {
            currentUser = session
            isAuthenticated = session.isValid
        }
    }
    
    /// Save session to UserDefaults
    internal func saveSession(_ session: UserSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
    
    private func generateCodeVerifier() -> String {
        // In production, generate a proper PKCE code verifier
        // For now, return a placeholder (Supabase handles this)
        return UUID().uuidString
    }
}
