import SwiftUI

// MARK: - FloatingWindowController
class FloatingWindowController: NSObject {
    
    private var window: NSWindow?
    private let aiService: AIService
    private let textManager: TextCaptureManager
    private let usageTracker: UsageTracker
    
    private var selectedText: String = ""
    private var selectedAction: AIAction = .improveClarity
    private var customInstruction: String = ""
    private var isProcessing: Bool = false
    
    init(
        aiService: AIService,
        textManager: TextCaptureManager,
        usageTracker: UsageTracker
    ) {
        self.aiService = aiService
        self.textManager = textManager
        self.usageTracker = usageTracker
        super.init()
    }
    
    deinit {
        window?.close()
    }
    
    func show(at position: NSPoint, withSelectedText text: String) {
        selectedText = text
        
        if window == nil {
            createWindow()
        }
        
        updateWindowPosition(at: position)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createWindow() {
        let contentView = FloatingActionView(
            selectedText: selectedText,
            onActionSelected: { [weak self] action in
                self?.handleActionSelected(action)
            },
            onCustomAction: { [weak self] instruction in
                self?.handleCustomAction(instruction)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 360, height: 500)
        
        window = NSWindow(
            contentRect: hostingController.view.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window?.contentViewController = hostingController
        window?.backgroundColor = .clear
        window?.isOpaque = false
        window?.hasShadow = true
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    private func updateWindowPosition(at position: NSPoint) {
        guard let window = window,
              let screen = NSScreen.main else { return }
        
        let windowSize = window.frame.size
        let screenFrame = screen.visibleFrame
        
        var x = position.x - windowSize.width / 2
        var y = position.y - windowSize.height - 20
        
        if x < screenFrame.minX {
            x = screenFrame.minX + 10
        } else if x + windowSize.width > screenFrame.maxX {
            x = screenFrame.maxX - windowSize.width - 10
        }
        
        if y < screenFrame.minY {
            y = position.y + 20
        }
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func handleActionSelected(_ action: AIAction) {
        guard !isProcessing else { return }
        isProcessing = true
        selectedAction = action
        
        processRewrite(action: action)
    }
    
    private func handleCustomAction(_ instruction: String) {
        guard !isProcessing else { return }
        isProcessing = true
        customInstruction = instruction
        
        processRewrite(action: .custom, customDescription: instruction)
    }
    
    private func processRewrite(action: AIAction, customDescription: String? = nil) {
        // Capture values locally to avoid Sendable issues
        let localAction = action
        let localCustomDescription = customDescription
        
        aiService.rewriteText(selectedText, action: localAction, customInstruction: localCustomDescription) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                switch result {
                case .success(let rewrittenText):
                    self?.replaceText(with: rewrittenText, action: localAction, customDescription: localCustomDescription)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func replaceText(with newText: String, action: AIAction, customDescription: String? = nil) {
        let localAction = action
        let localCustomDescription = customDescription
        
        textManager.replaceSelectedText(with: newText) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.recordUsage(action: localAction, rewrittenText: newText, customDescription: localCustomDescription)
                    self?.dismiss()
                case .failure(let error):
                    self?.showTextReplacementError(error)
                }
            }
        }
    }
    
    private func recordUsage(action: AIAction, rewrittenText: String, customDescription: String?) {
        Task { @MainActor in
            let actionName = customDescription ?? action.displayName
            usageTracker.recordUsage(
                action: action,
                originalText: selectedText,
                rewrittenText: rewrittenText,
                model: "gpt-oss-120b",
                tokensIn: selectedText.count / 4,
                tokensOut: rewrittenText.count / 4
            )
        }
    }
    
    private func dismiss() {
        window?.orderOut(nil)
    }
    
    private func showError(_ error: AIServiceError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        
        switch error {
        case .networkError:
            alert.messageText = "Network Error"
            alert.informativeText = "Unable to connect to AI service. Please check your internet connection."
        case .apiError(let message):
            alert.messageText = "AI Service Error"
            alert.informativeText = message
        case .rateLimited:
            alert.messageText = "Rate Limited"
            alert.informativeText = "Too many requests. Please wait a moment and try again."
        default:
            alert.messageText = "Error"
            alert.informativeText = "Something went wrong. Please try again."
        }
        
        alert.runModal()
        dismiss()
    }
    
    @MainActor
    private func showTextReplacementError(_ error: TextCaptureError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replacement Failed"
        alert.informativeText = "Unable to replace the selected text. Please try again."
        alert.runModal()
    }
}
