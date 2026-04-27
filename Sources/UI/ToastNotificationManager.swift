import Cocoa

// MARK: - ToastNotificationManager
/// Manages aesthetic toast notifications for the app
class ToastNotificationManager {
    
    static let shared = ToastNotificationManager()
    
    private var currentWindow: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentToastId: UUID?
    private let queue = DispatchQueue.main
    
    private init() {}
    
    /// Shows a toast notification with the given message
    /// - Parameters:
    ///   - message: The main message to display
    ///   - subtitle: Optional subtitle
    ///   - type: The type of toast (error, warning, info, success)
    ///   - duration: How long to show the toast (default 3 seconds)
    func showToast(
        message: String,
        subtitle: String? = nil,
        type: ToastType = .info,
        duration: TimeInterval = 3.0
    ) {
        queue.async { [weak self] in
            self?.dismissWorkItem?.cancel()
            self?.dismissCurrentToast()
            self?.createAndShowToast(message: message, subtitle: subtitle, type: type, duration: duration)
        }
    }
    
    private func createAndShowToast(
        message: String,
        subtitle: String?,
        type: ToastType,
        duration: TimeInterval
    ) {
        // Get the main screen
        guard let screen = NSScreen.main else { return }
        let toastId = UUID()
        currentToastId = toastId
        
        let toastWidth: CGFloat = 320
        let toastHeight: CGFloat = subtitle != nil ? 70 : 50
        
        // Position at top-center of screen (safer for all screen sizes)
        let screenFrame = screen.frame
        let x = (screenFrame.width - toastWidth) / 2
        let y = screenFrame.height - toastHeight - 80 // 80px from top to account for menu bar
        
        // Colors based on type - cream aesthetic
        let creamBg = NSColor(red: 0.9921569, green: 0.9921569, blue: 0.9843137, alpha: 1.0)
        let brownAccent = NSColor(red: 0.55, green: 0.32, blue: 0.22, alpha: 1.0)
        let darkText = NSColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1.0)
        let mutedText = NSColor(red: 0.48, green: 0.45, blue: 0.42, alpha: 1.0)
        
        let (backgroundColor, iconColor, textColor, iconName): (NSColor, NSColor, NSColor, String)
        switch type {
        case .error:
            backgroundColor = creamBg
            iconColor = NSColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1.0)
            textColor = darkText
            iconName = "exclamationmark.circle.fill"
        case .warning:
            backgroundColor = creamBg
            iconColor = NSColor(red: 0.95, green: 0.65, blue: 0.20, alpha: 1.0)
            textColor = darkText
            iconName = "exclamationmark.triangle.fill"
        case .success:
            backgroundColor = creamBg
            iconColor = NSColor(red: 0.25, green: 0.65, blue: 0.35, alpha: 1.0)
            textColor = darkText
            iconName = "checkmark.circle.fill"
        case .info:
            backgroundColor = creamBg
            iconColor = brownAccent
            textColor = darkText
            iconName = "info.circle.fill"
        case .limitExceeded:
            backgroundColor = creamBg
            iconColor = brownAccent
            textColor = darkText
            iconName = "crown.fill"
        }
        
        // Create the toast window
        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: toastWidth, height: toastHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false  // Allow mouse events for click to dismiss
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Create container view with close button
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = backgroundColor.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.shadowColor = NSColor.black.cgColor
        containerView.layer?.shadowOpacity = 0.15
        containerView.layer?.shadowRadius = 12
        containerView.layer?.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor(red: 0.85, green: 0.82, blue: 0.78, alpha: 1.0).cgColor
        
        // Add click gesture to dismiss
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleToastClick))
        containerView.addGestureRecognizer(clickGesture)
        
        // Icon
        let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        let iconView = NSImageView(image: iconImage!)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = iconColor
        containerView.addSubview(iconView)
        
        // Message label
        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = textColor
        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        containerView.addSubview(messageLabel)
        
        // Close button
        let closeButton = NSButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = mutedText
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(dismissCurrentToast)
        closeButton.toolTip = "Click to dismiss"
        containerView.addSubview(closeButton)
        
        // Subtitle label (if provided)
        var subtitleLabel: NSTextField?
        if let subtitle = subtitle {
            subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel?.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel?.textColor = mutedText
            subtitleLabel?.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            if let subtitleLabel = subtitleLabel {
                containerView.addSubview(subtitleLabel)
            }
        }
        
        // Constraints
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            
            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8)
        ])
        
        if let subtitleLabel = subtitleLabel {
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
                subtitleLabel.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 2),
                subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12)
            ])
        } else {
            NSLayoutConstraint.activate([
                messageLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
            ])
        }
        
        window.contentView = containerView
        
        // Show the window
        window.orderFrontRegardless()
        currentWindow = window
        
        // Auto-dismiss after duration
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissToastIfCurrent(toastId)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func dismissToastIfCurrent(_ toastId: UUID) {
        guard currentToastId == toastId else { return }
        dismissCurrentToast()
    }
    
    @objc private func handleToastClick() {
        dismissCurrentToast()
    }
    
    @objc private func dismissCurrentToast() {
        guard let window = currentWindow else { return }
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        currentToastId = nil
        let windowToClose = window
        
        // Fade out animation with a fallback close in case completion isn't called.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            windowToClose.animator().alphaValue = 0
        }, completionHandler: {
            windowToClose.orderOut(nil)
            if self.currentWindow === windowToClose {
                self.currentWindow = nil
            }
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            if self.currentWindow === windowToClose {
                windowToClose.orderOut(nil)
                self.currentWindow = nil
            }
        }
    }
}

// MARK: - Toast Type
enum ToastType {
    case error
    case warning
    case success
    case info
    case limitExceeded
}
