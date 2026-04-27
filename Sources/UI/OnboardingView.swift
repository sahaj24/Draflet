import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentShortcut: String = "⌘⇧A"
    @State private var isEditingShortcut: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
                // Left Sidebar
                VStack(spacing: 0) {
                    Spacer()
                    
                    DraftletLogoMark(
                        tileColor: .white,
                        iconSize: 34,
                        tileSize: 64,
                        tileCornerRadius: 16
                    )
                    .padding(.bottom, 24)
                    
                    Text("Draftlet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .padding(.bottom, 8)
                    
                    Text("Your intelligent companion, integrated into every workflow.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.48, green: 0.45, blue: 0.42))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .frame(width: 240)
                .background(Color(red: 0.969, green: 0.953, blue: 0.933))
                .overlay(
                    Rectangle()
                        .fill(Color(red: 0.89, green: 0.88, blue: 0.86).opacity(0.5))
                        .frame(width: 1),
                    alignment: .trailing
                )
                
                // Right Content Area
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Quick Setup")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                            .padding(.bottom, 32)
                            .padding(.top, 48)
                        
                        // Step 1 - Accessibility Permissions
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.96, green: 0.96, blue: 0.94))
                                    .frame(width: 32, height: 32)
                                Text("1")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.38))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Enable Accessibility")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                                
                                Text("Draftlet needs permission to read text from your active applications.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.48, green: 0.45, blue: 0.42))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 4)
                                
                                Button(action: {
                                    requestAccessibilityPermission()
                                }) {
                                    Text("Grant Permission")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.42))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(red: 0.89, green: 0.88, blue: 0.86), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.bottom, 40)
                        
                        // Step 2 - Keyboard Shortcut
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.96, green: 0.96, blue: 0.94))
                                    .frame(width: 32, height: 32)
                                Text("2")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.38))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Set Default Shortcut")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                                
                                Text("Summon the assistant instantly from anywhere.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.48, green: 0.45, blue: 0.42))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 4)
                                
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Text("⌘")
                                            .font(.system(size: 14))
                                        Text("Command")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.42))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(red: 0.89, green: 0.88, blue: 0.86), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    
                                    Text("+")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.63, green: 0.63, blue: 0.61))
                                    
                                    HStack(spacing: 4) {
                                        Text("⇧")
                                            .font(.system(size: 14))
                                        Text("Shift")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.42))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(red: 0.89, green: 0.88, blue: 0.86), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    
                                    Text("+")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.63, green: 0.63, blue: 0.61))
                                    
                                    Text("A")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.42))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(red: 0.89, green: 0.88, blue: 0.86), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    
                                    Button(action: {
                                        // TODO: Implement shortcut change
                                    }) {
                                        Text("CHANGE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color(red: 0.63, green: 0.63, blue: 0.61))
                                            .tracking(1)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.leading, 4)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Footer Actions - Only Get Started button
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                isOnboardingComplete = true
                            }) {
                                Text("Get Started")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 10)
                                    .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                        .overlay(
                            Rectangle()
                                .fill(Color(red: 0.96, green: 0.96, blue: 0.94))
                                .frame(height: 1),
                            alignment: .top
                        )
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.992, green: 0.984, blue: 0.969))
            }
        .frame(width: 720, height: 520)
        .background(Color(red: 0.992, green: 0.984, blue: 0.969))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            // Permission already granted
            print("Accessibility permission granted")
        } else {
            // System will show permission dialog
            print("Requesting accessibility permission")
        }
    }
}

// MARK: - App Logo Mark (shared)
struct DraftletLogoMark: View {
    let tileColor: Color
    var iconSize: CGFloat = 40
    var tileSize: CGFloat = 80
    var tileCornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                .fill(tileColor)
                .frame(width: tileSize, height: tileSize)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)

            if let logoImage = Self.resolveDraftletLogoImage() {
                Image(nsImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: iconSize * 0.8, weight: .regular))
                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
            }
        }
        .accessibilityLabel("Draftlet logo")
    }

    private static func resolveDraftletLogoImage() -> NSImage? {
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
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isOnboardingComplete: .constant(false))
    }
}
