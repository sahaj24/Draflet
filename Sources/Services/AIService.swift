import Foundation

// MARK: - Custom Prompt
struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var shortcutKey: String?
    var shortcutModifiers: [String]?
    
    init(id: UUID = UUID(), name: String, content: String, shortcutKey: String? = nil, shortcutModifiers: [String]? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.shortcutKey = shortcutKey
        self.shortcutModifiers = shortcutModifiers
    }
}

// MARK: - AIAction
/// Defines the available AI transformation actions
enum AIAction: String, CaseIterable, Identifiable {
    case fixGrammar = "fix_grammar"
    case improveClarity = "improve_clarity"
    case shorten = "shorten"
    case makeFunny = "make_funny"
    case makeProfessional = "make_professional"
    case smartPrompt = "smart_prompt"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .improveClarity: return "Improve Clarity"
        case .shorten: return "Shorten"
        case .makeFunny: return "Make Funny"
        case .makeProfessional: return "Make Professional"
        case .smartPrompt: return "Smart Prompt"
        case .custom: return "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .fixGrammar: return "checkmark.circle"
        case .improveClarity: return "sparkles"
        case .shorten: return "arrow.compress"
        case .makeFunny: return "face.smiling"
        case .makeProfessional: return "briefcase"
        case .smartPrompt: return "wand.and.stars"
        case .custom: return "pencil"
        }
    }
    
    var description: String {
        switch self {
        case .fixGrammar: return "Fix all grammar and spelling errors"
        case .improveClarity: return "Make text clearer and more concise"
        case .shorten: return "Reduce text length while keeping meaning"
        case .makeFunny: return "Add humor and make it entertaining"
        case .makeProfessional: return "Formal tone for business communication"
        case .smartPrompt: return "Add (instructions) at the end of your text"
        case .custom: return "Your custom instruction"
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .fixGrammar:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Fix grammar, spelling, and punctuation errors instantly.
            
            Behavior rules:
            - Preserve the exact meaning
            - Fix all grammar, spelling, and punctuation errors
            - Keep the original tone and style
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            - If input is already perfect, return it unchanged
            - If input is broken, fix it intelligently
            """
        case .improveClarity:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Improve clarity and flow instantly.
            
            Behavior rules:
            - Preserve meaning unless instructed otherwise
            - Improve grammar, clarity, and flow
            - Make it more concise and easier to understand
            - Keep it natural and avoid sounding like AI-generated text
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            - If input is very short, slightly enhance it
            - If input is broken, fix intelligently
            """
        case .shorten:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Reduce length without losing meaning.
            
            Behavior rules:
            - Preserve the core message completely
            - Be concise - cut unnecessary words and phrases
            - Remove fluff and redundancy
            - Keep the natural flow
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            - Maintain the original tone
            """
        case .makeFunny:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Add light humor, keep it witty, not cringe.
            
            Behavior rules:
            - Preserve the main point and meaning
            - Rewrite with light humor
            - Make it witty and entertaining
            - Keep it natural, not forced or cringe
            - Casual, friendly tone
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            """
        case .makeProfessional:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Make it clear, polite, and concise.
            
            Behavior rules:
            - Preserve meaning
            - Clear, polite, and concise business language
            - Professional tone without being stiff
            - Improve grammar and flow
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            - Use appropriate professional terminology
            """
        case .smartPrompt:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Detect any instruction in brackets at the end of the user's text and apply it.
            
            Examples of bracket instructions:
            - (make it shorter) → Shorten the text
            - (write it as code) → Convert to code format
            - (make it funny) → Add humor
            - (translate to Spanish) → Translate text
            
            Behavior rules:
            - Remove the bracket instruction from the output
            - Apply the instruction to transform the remaining text
            - If no brackets found, intelligently improve the text
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            """
        case .custom:
            return """
            You are a fast, precise AI writing assistant embedded at the OS level.
            
            Your task: Rewrite selected text according to the user's specific instruction.
            
            Behavior rules:
            - Preserve meaning unless instructed otherwise
            - Match the appropriate tone based on the instruction
            - If no instruction is given, intelligently improve the text
            - Keep it concise and natural
            - Avoid sounding like AI-generated text
            - Do not explain anything
            - Do not add extra sentences
            - Return only the final rewritten text
            - If input is already perfect, return it unchanged
            - If input is broken, fix intelligently
            """
        }
    }
}

// MARK: - AIServiceError
enum AIServiceError: Error {
    case networkError
    case invalidResponse
    case apiError(String)
    case rateLimited
    case insufficientTokens(Int) // remaining tokens
    case noSelection
}

/// Handles communication with Cloudflare Worker proxy
class AIService {
    
    // Cloudflare Worker proxy configuration
    private let proxyBaseURL: String
    
    // Supabase configuration for auth
    private let supabaseURL: String
    private let supabaseAnonKey: String
    private var supabaseToken: String?
    
    private let session: URLSession
    
    init() {
        let env = ProcessInfo.processInfo.environment
        self.proxyBaseURL = env["DRAFLET_PROXY_BASE_URL"]
            ?? env["PROXY_BASE_URL"]
            ?? "https://ai-writing-proxy.sahajgupta12345.workers.dev"
        self.supabaseURL = env["DRAFLET_SUPABASE_URL"]
            ?? env["SUPABASE_URL"]
            ?? "https://kgypcdyiszmsdvxzkocq.supabase.co"
        self.supabaseAnonKey = env["DRAFLET_SUPABASE_ANON_KEY"]
            ?? env["SUPABASE_ANON_KEY"]
            ?? ""

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 120.0
        self.session = URLSession(configuration: config)
        
        // Try to get existing token or create anonymous user
        Task {
            await initializeAuth()
        }
    }
    
    /// Initialize Supabase auth (anonymous for now)
    private func initializeAuth() async {
        // For now, we'll use a simple device-based identifier
        // In production, you'd implement proper user signup/login
        let deviceId = getOrCreateDeviceId()
        
        // Try to sign in or sign up with the device ID
        await signInWithDeviceId(deviceId)
    }
    
    /// Get or create a unique device ID
    private func getOrCreateDeviceId() -> String {
        let key = "AIWritingAssistantDeviceId"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    /// Sign in with device ID (creates user if doesn't exist)
    private func signInWithDeviceId(_ deviceId: String) async {
        guard !supabaseAnonKey.isEmpty else {
            print("Missing Supabase anon key. Set DRAFLET_SUPABASE_ANON_KEY in your environment.")
            return
        }

        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else { return }
        
        // For anonymous users, we'll use a simple approach
        // In production, implement proper email/password or OAuth
        let requestBody: [String: Any] = [
            "email": "\(deviceId)@aiwriting.local",
            "password": deviceId
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(supabaseAnonKey)", forHTTPHeaderField: "apikey")
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                self.supabaseToken = accessToken
            }
        } catch {
            print("Auth error: \(error)")
        }
    }
    
    func rewriteText(
        _ text: String,
        action: AIAction,
        customInstruction: String? = nil,
        customSystemPrompt: String? = nil,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        Task {
            await performRewrite(
                text: text,
                action: action,
                customInstruction: customInstruction,
                customSystemPrompt: customSystemPrompt,
                completion: completion
            )
        }
    }
    
    /// Internal method to perform the actual AI rewrite after token check
    private func performRewrite(
        text: String,
        action: AIAction,
        customInstruction: String?,
        customSystemPrompt: String?,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) async {
        guard let url = URL(string: proxyBaseURL) else {
            await MainActor.run {
                completion(.failure(.networkError))
            }
            return
        }

        guard let token = await AuthManager.shared.getValidToken() else {
            await MainActor.run {
                completion(.failure(.apiError("Session expired. Please sign in again.")))
            }
            return
        }
        
        let effectiveCustomPrompt = customSystemPrompt
            ?? customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? action.systemPrompt

        let requestBody: [String: Any] = [
            "text": text,
            "action": action.rawValue,
            "customPrompt": effectiveCustomPrompt,
            "supabaseToken": token
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            await MainActor.run {
                completion(.failure(.invalidResponse))
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                Task { @MainActor in
                    completion(.failure(.networkError))
                }
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                Task { @MainActor in
                    completion(.failure(.invalidResponse))
                }
                return
            }
            
            if httpResponse.statusCode == 402 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let remaining = json["remaining"] as? Int ?? 0
                    Task { @MainActor in
                        completion(.failure(.insufficientTokens(remaining)))
                    }
                    return
                }
            }

            if httpResponse.statusCode == 429 {
                // Daily limit exceeded
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = json["error"] as? String,
                   errorMsg == "Daily limit exceeded" {
                    // Extract remaining info if available
                    let limit = json["limit"] as? Int ?? 20
                    let used = json["used"] as? Int ?? limit
                    print("Daily limit exceeded: \(used)/\(limit)")
                }
                Task { @MainActor in
                    completion(.failure(.rateLimited))
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? String {
                    Task { @MainActor in
                        completion(.failure(.apiError(error)))
                    }
                } else {
                    Task { @MainActor in
                        completion(.failure(.apiError("HTTP \(httpResponse.statusCode)")))
                    }
                }
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool,
                  success == true else {
                let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("Invalid success payload from worker: \(rawBody)")
                Task { @MainActor in
                    completion(.failure(.invalidResponse))
                }
                return
            }

            let rewrittenText: String
            if let textValue = json["text"] as? String {
                rewrittenText = textValue
            } else if let textArray = json["text"] as? [[String: Any]] {
                rewrittenText = textArray.compactMap { $0["text"] as? String ?? $0["content"] as? String }.joined()
            } else if let textObj = json["text"] as? [String: Any],
                      let textValue = textObj["text"] as? String ?? textObj["content"] as? String {
                rewrittenText = textValue
            } else {
                let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("Missing usable text in worker payload: \(rawBody)")
                Task { @MainActor in
                    completion(.failure(.apiError("AI response format changed")))
                }
                return
            }

            let cleanedContent = rewrittenText.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if let remaining = json["remaining"] as? Int {
                Task { @MainActor in
                    TokenManager.shared.tokensRemaining = max(0, remaining)
                }
                Task {
                    await TokenManager.shared.fetchTokens()
                }
            }
            
            Task { @MainActor in
                completion(.success(cleanedContent))
            }
        }
        
        task.resume()
    }
}
