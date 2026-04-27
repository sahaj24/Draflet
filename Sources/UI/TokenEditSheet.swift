import SwiftUI

// MARK: - Token Edit Sheet
/// Modal sheet for manually editing token count (admin use)
struct TokenEditSheet: View {
    @Binding var tokenAmount: String
    let currentTokens: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void
    
    @State private var selectedPlan: String = "free"
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                Text("Edit Tokens")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            
            // Current status
            HStack {
                Text("Current: \(currentTokens) tokens")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Token input
            VStack(alignment: .leading, spacing: 8) {
                Text("New Token Amount")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Enter amount", text: $tokenAmount)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // Plan selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Plan Type")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("Plan", selection: $selectedPlan) {
                    Text("Free (20 daily)").tag("free")
                    Text("Pro (500 daily)").tag("pro")
                    Text("Enterprise (Custom)").tag("enterprise")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 280)
            }
            
            // Quick set buttons
            HStack(spacing: 12) {
                Button("Set Free (20)") {
                    tokenAmount = "20"
                    selectedPlan = "free"
                }
                .buttonStyle(TokenQuickSetButtonStyle(color: .blue))
                
                Button("Set Pro (500)") {
                    tokenAmount = "500"
                    selectedPlan = "pro"
                }
                .buttonStyle(TokenQuickSetButtonStyle(color: .green))
                
                Button("Reset (20)") {
                    tokenAmount = "20"
                    selectedPlan = "free"
                }
                .buttonStyle(TokenQuickSetButtonStyle(color: .orange))
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save Changes") {
                    if let amount = Int(tokenAmount), amount >= 0 {
                        onSave(amount)
                        onCancel()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(Int(tokenAmount) == nil)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

// MARK: - Token Quick Set Button Style
struct TokenQuickSetButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }
}
