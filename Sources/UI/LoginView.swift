import SwiftUI
import AuthenticationServices

// MARK: - Login View
/// Clean login view matching the Draftlet design aesthetic
struct LoginView: View {
    @ObservedObject var authManager = AuthManager.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Clean palette matching the design
    private let bgColor = Color(NSColor(red: 0.898, green: 0.898, blue: 0.882, alpha: 1.0))
    private let cardBg = Color(NSColor(red: 0.992, green: 0.984, blue: 0.969, alpha: 1.0))
    private let buttonBg = Color(NSColor(red: 0.231, green: 0.231, blue: 0.231, alpha: 1.0))
    private let textColor = Color(NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0))
    private let mutedColor = Color(NSColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1.0))
    
    var body: some View {
        ZStack {
            // Background
            bgColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Main content
                VStack(spacing: 32) {
                    DraftletLogoMark(
                        tileColor: Color(red: 0.969, green: 0.953, blue: 0.933),
                        iconSize: 40,
                        tileSize: 80,
                        tileCornerRadius: 20
                    )
                    
                    // Title and subtitle
                    VStack(spacing: 12) {
                        Text("Sign In to Draftlet")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(textColor)
                        
                        Text("To get started, please sign in via your web browser. This will securely link your account to the desktop app.")
                            .font(.system(size: 14))
                            .foregroundColor(mutedColor)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: 380)
                    }
                    
                    // Login button
                    Button(action: openWebsiteToLogin) {
                        HStack(spacing: 8) {
                            Text("Sign In with Browser")
                                .font(.system(size: 15, weight: .medium))
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 260, height: 48)
                        .background(buttonBg)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(buttonBg)
                    }
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 24) {
                    Text("DRAFTLET IVORY ATELIER © 2024")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(mutedColor.opacity(0.6))
                        .tracking(1.2)
                    
                    // Feature tags
                    HStack(spacing: 32) {
                        Text("Privacy First")
                            .font(.system(size: 10))
                            .foregroundColor(mutedColor.opacity(0.5))
                        
                        Circle()
                            .fill(mutedColor.opacity(0.3))
                            .frame(width: 3, height: 3)
                        
                        Text("Secure Bridge Architecture")
                            .font(.system(size: 10))
                            .foregroundColor(mutedColor.opacity(0.5))
                        
                        Circle()
                            .fill(mutedColor.opacity(0.3))
                            .frame(width: 3, height: 3)
                        
                        Text("Encrypted Auth")
                            .font(.system(size: 10))
                            .foregroundColor(mutedColor.opacity(0.5))
                    }
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBg)
        }
        .frame(width: 640, height: 480)
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Check if already logged in via deep link
            checkForExistingSession()
        }
    }
    
    private func openWebsiteToLogin() {
        // Open the website login page with macapp flag
        let loginURL = URL(string: "http://localhost:8081/login?from=macapp")!
        NSWorkspace.shared.open(loginURL)
        
        // Show instruction toast
        ToastNotificationManager.shared.showToast(
            message: "Browser opened",
            subtitle: "Please login on the website, then return to the app",
            type: .info,
            duration: 4.0
        )
    }
    
    private func checkForExistingSession() {
        // Try to load existing session from UserDefaults
        if let sessionData = UserDefaults.standard.data(forKey: "AIWritingAssistantUserSession"),
           let session = try? JSONDecoder().decode(UserSession.self, from: sessionData) {
            
            // Check if token is still valid
            if session.expiresAt > Date() {
                authManager.currentUser = session
                authManager.isAuthenticated = true
                NotificationCenter.default.post(name: NSNotification.Name("AuthStateChanged"), object: nil)
            }
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    let accentColor: Color
    let mutedColor: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
                .frame(width: 22)
            
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(mutedColor)
            
            Spacer()
        }
    }
}

// MARK: - User Profile View
struct UserProfileView: View {
    @ObservedObject var authManager = AuthManager.shared
    
    // Premium palette
    private let accentColor = Color(NSColor(red: 0.55, green: 0.32, blue: 0.22, alpha: 1.0))
    private let textColor = Color(NSColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0))
    private let mutedColor = Color(NSColor(red: 0.48, green: 0.45, blue: 0.42, alpha: 1.0))
    private let borderColor = Color(NSColor(red: 0.82, green: 0.79, blue: 0.74, alpha: 1.0))
    
    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                if let avatarUrl = authManager.currentUser?.avatarUrl,
                   let _ = URL(string: avatarUrl) {
                    Text(userInitials)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accentColor)
                } else {
                    Text(userInitials)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }
            
            // User info
            VStack(spacing: 4) {
                if let displayName = authManager.currentUser?.displayName {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                }
                
                if let email = authManager.currentUser?.email {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundColor(mutedColor)
                }
            }
            
            // Plan badge
            HStack(spacing: 4) {
                Image(systemName: authManager.currentUser?.plan == "pro" ? "crown.fill" : "person.fill")
                    .font(.system(size: 10))
                Text(authManager.currentUser?.plan.capitalized ?? "Free")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                authManager.currentUser?.plan == "pro"
                    ? Color(NSColor(red: 0.95, green: 0.85, blue: 0.25, alpha: 0.3))
                    : Color.gray.opacity(0.15)
            )
            .foregroundColor(
                authManager.currentUser?.plan == "pro"
                    ? accentColor
                    : mutedColor
            )
            .cornerRadius(10)
            
            Divider()
                .padding(.vertical, 4)
            
            // Sign out button
            Button(action: signOut) {
                Label("Sign Out", systemImage: "arrow.right.square")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(mutedColor)
        }
        .padding(16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 0.5))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
    }
    
    private var userInitials: String {
        let name = authManager.currentUser?.displayName ??
                   authManager.currentUser?.email?.components(separatedBy: "@").first ??
                   "User"
        let components = name.split(separator: " ")
        if components.count > 1 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private func signOut() {
        authManager.signOut()
    }
}

// MARK: - Presentation Context Provider
class WindowPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var window: NSWindow?
    
    init(window: NSWindow) {
        self.window = window
        super.init()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window ?? NSWindow()
    }
}
