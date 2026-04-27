import SwiftUI

// MARK: - FloatingActionView
/// Premium floating AI action panel with glassmorphism design
struct FloatingActionView: View {
    
    let selectedText: String
    let onActionSelected: (AIAction) -> Void
    let onCustomAction: (String) -> Void
    let onDismiss: () -> Void
    
    @State private var selectedAction: AIAction = .improveClarity
    @State private var customInstruction: String = ""
    @State private var isShowingCustom: Bool = false
    @State private var isAnimating: Bool = false
    @State private var hoveredAction: AIAction?
    @FocusState private var isCustomFieldFocused: Bool
    
    // Premium palette
    private let glassBg = Color.white.opacity(0.72)
    private let accentColor = Color(NSColor(red: 0.45, green: 0.39, blue: 0.33, alpha: 1.0))
    private let textColor = Color(NSColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0))
    private let mutedColor = Color(NSColor(red: 0.48, green: 0.45, blue: 0.42, alpha: 1.0))
    private let borderColor = Color(NSColor(red: 0.82, green: 0.79, blue: 0.74, alpha: 1.0))
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            actionsGrid
            Divider().padding(.horizontal, 16)
            customSection
        }
        .frame(width: 360)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(glassBg)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.15), radius: 50, x: 0, y: 25)
        .shadow(color: accentColor.opacity(0.1), radius: 20, x: 0, y: 10)
        .scaleEffect(isAnimating ? 1.0 : 0.85)
        .opacity(isAnimating ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isAnimating = true
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image("draftlet-logo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("Draftlet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isAnimating = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(mutedColor)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.5))
                                .overlay(Circle().stroke(borderColor, lineWidth: 0.5))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack(alignment: .top, spacing: 10) {
                Text("\"" + selectedText + "\"")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(textColor.opacity(0.85))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var actionsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(AIAction.allCases.filter { $0 != .custom }) { action in
                PremiumActionButton(
                    action: action,
                    isSelected: selectedAction == action,
                    isHovered: hoveredAction == action,
                    accentColor: accentColor,
                    textColor: textColor,
                    onTap: {
                        selectedAction = action
                        onActionSelected(action)
                    }
                )
                .onHover { isHovered in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredAction = isHovered ? action : nil
                    }
                }
            }
        }
        .padding(16)
    }
    
    private var customSection: some View {
        VStack(spacing: 12) {
            if isShowingCustom {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)
                        Text("Custom Instruction")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    
                    HStack(spacing: 10) {
                        TextField("e.g., Make it poetic", text: $customInstruction)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 14))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(borderColor, lineWidth: 1)
                                    )
                            )
                            .focused($isCustomFieldFocused)
                            .onSubmit {
                                if !customInstruction.isEmpty {
                                    onCustomAction(customInstruction)
                                }
                            }
                        
                        Button(action: {
                            if !customInstruction.isEmpty {
                                onCustomAction(customInstruction)
                            }
                        }) {
                            Image(systemName: "arrow.forward.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(accentColor)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(customInstruction.isEmpty)
                        .opacity(customInstruction.isEmpty ? 0.3 : 1.0)
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.35)) {
                        isShowingCustom = true
                        isCustomFieldFocused = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 14))
                        Text("Custom Instruction...")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(accentColor)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(borderColor.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            HStack(spacing: 8) {
                Text("Press")
                    .font(.system(size: 10))
                    .foregroundColor(mutedColor)
                KeyBadge(text: "⌘1", mutedColor: mutedColor)
                Text("Fix")
                    .font(.system(size: 10))
                    .foregroundColor(mutedColor)
                KeyBadge(text: "⌘2", mutedColor: mutedColor)
                Text("Clarity")
                    .font(.system(size: 10))
                    .foregroundColor(mutedColor)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

struct PremiumActionButton: View {
    let action: AIAction
    let isSelected: Bool
    let isHovered: Bool
    let accentColor: Color
    let textColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(
                            color: isSelected ? accentColor.opacity(0.35) : Color.clear,
                            radius: isSelected ? 12 : 0,
                            x: 0,
                            y: isSelected ? 6 : 0
                        )
                    
                    Image(systemName: action.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isSelected ? .white : accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                
                Text(action.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? accentColor : textColor)
            }
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHovered ? Color.white.opacity(0.4) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? accentColor.opacity(0.4) : (isHovered ? accentColor.opacity(0.2) : Color.clear),
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered && !isSelected ? 1.03 : (isSelected ? 0.97 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isSelected)
    }
}

struct KeyBadge: View {
    let text: String
    let mutedColor: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(mutedColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(mutedColor.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}
