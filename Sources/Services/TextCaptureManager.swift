import Cocoa
import ApplicationServices

// MARK: - TextCaptureError
/// Errors that can occur during text capture operations
enum TextCaptureError: Error {
    case noSelection           // No text is currently selected
    case accessibilityDenied   // Accessibility permissions not granted
    case captureFailed         // General capture failure
    case replacementFailed     // Failed to replace text
}

// MARK: - TextCaptureManager
/// Manages text capture and replacement using macOS Accessibility APIs
/// This class handles reading selected text from any application and replacing it with AI-generated content
class TextCaptureManager {
    
    // MARK: - Properties
    
    /// Cache for the original text to support undo functionality
    private var originalTextCache: String?
    private var targetElement: AXUIElement?
    
    // MARK: - Public Methods
    
    /// Captures selected text, or current line/paragraph if no selection
    /// - Parameter completion: Callback with the captured text or error
    func captureTextOrCurrentLine(completion: @escaping (Result<(text: String, isSelection: Bool), TextCaptureError>) -> Void) {
        // Check accessibility permissions first
        guard checkAccessibilityPermissions() else {
            completion(.failure(.accessibilityDenied))
            return
        }
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            completion(.failure(.captureFailed))
            return
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Get the focused UI element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            // Try clipboard fallback if accessibility fails
            tryClipboardCapture(completion: completion)
            return
        }
        
        // Store reference to the element for later replacement
        targetElement = (element as! AXUIElement)
        
        // First try to get selected text
        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            targetElement!,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )
        
        if textResult == .success, let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            // We have selected text - use it
            originalTextCache = selectedText
            completion(.success((text: selectedText, isSelection: true)))
            return
        }
        
        // No selection - try to get current line/paragraph from cursor position
        if tryCaptureCurrentParagraph(element: targetElement!, completion: completion) {
            return
        }
        
        // No selection via accessibility - try AppleScript for specific apps, then clipboard fallback
        tryAppleScriptCapture(completion: completion)
    }
    
    /// Try using AppleScript to get selected text from specific apps
    private func tryAppleScriptCapture(completion: @escaping (Result<(text: String, isSelection: Bool), TextCaptureError>) -> Void) {
        // Get the frontmost app name
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            completion(.failure(.captureFailed))
            return
        }
        
        let appName = frontmostApp.localizedName ?? ""
        
        // AppleScript to get selected text - works with many apps
        var scriptSource = ""
        
        if appName.contains("Chrome") || appName.contains("Brave") || appName.contains("Edge") {
            // For Chromium browsers
            scriptSource = """
            tell application "System Events"
                tell application process "\(appName)"
                    set selectedText to value of attribute "AXSelectedText" of text area 1 of group 1 of splitter group 1 of window 1
                end tell
            end tell
            return selectedText
            """
        } else if appName.contains("Code") || appName.contains("Cursor") {
            // For VS Code and similar
            scriptSource = """
            tell application "System Events"
                keystroke "c" using command down
            end tell
            delay 0.1
            return ""
            """
            // This triggers copy and we fall back to clipboard check
        } else {
            // Generic script for any app
            scriptSource = """
            tell application "System Events"
                tell application process "\(appName)"
                    set selectedText to value of attribute "AXSelectedText" of (first text area whose focused is true)
                end tell
            end tell
            return selectedText
            """
        }
        
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        let result = script?.executeAndReturnError(&errorInfo)
        if let result = result {
            if let text = result.stringValue, !text.isEmpty {
                self.originalTextCache = text
                self.targetElement = nil
                completion(.success((text: text, isSelection: true)))
                return
            }
        }
        
        // AppleScript failed, fall back to clipboard
        tryClipboardCapture(completion: completion)
    }
    
    /// Fallback method using clipboard to capture selected text
    /// This works with apps that don't expose text via Accessibility APIs (Chrome, VS Code, etc.)
    private func tryClipboardCapture(attempt: Int = 1, completion: @escaping (Result<(text: String, isSelection: Bool), TextCaptureError>) -> Void) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount
        
        // Make sure we're not the frontmost app so events go to the target
        NSApp.deactivate()
        
        // Wait longer for keys to be released and target app to activate
        // First attempt: 0.2s, Second attempt: 0.4s
        let initialDelay = attempt == 1 ? 0.2 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            // First try to just copy (if text is already selected)
            self.simulateCopyCommand()
            
            // Check clipboard after a delay - Chrome/VS Code need more time
            let checkDelay = attempt == 1 ? 0.4 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + checkDelay) {
                let newContents = pasteboard.string(forType: .string)
                let newChangeCount = pasteboard.changeCount
                
                // If clipboard changed and has content, we captured selected text
                if newChangeCount != oldChangeCount, let capturedText = newContents, !capturedText.isEmpty {
                    // Restore original clipboard
                    if let oldContents = oldContents {
                        pasteboard.clearContents()
                        pasteboard.setString(oldContents, forType: .string)
                    }
                    
                    self.originalTextCache = capturedText
                    // Mark that we used clipboard method so replacement uses paste
                    self.targetElement = nil
                    completion(.success((text: capturedText, isSelection: true)))
                    return
                }
                
                // No text selected - try to select current line and copy
                self.trySelectAndCopyLine(
                    oldContents: oldContents,
                    oldChangeCount: oldChangeCount,
                    pasteboard: pasteboard,
                    attempt: attempt,
                    completion: completion
                )
            }
        }
    }
    
    /// Try to select the current line using Cmd+L (common in code editors) and then copy
    private func trySelectAndCopyLine(
        oldContents: String?,
        oldChangeCount: Int,
        pasteboard: NSPasteboard,
        attempt: Int,
        completion: @escaping (Result<(text: String, isSelection: Bool), TextCaptureError>) -> Void
    ) {
        // Make sure we're not the frontmost app
        NSApp.deactivate()
        
        // Try to select current line (Cmd+L is common in VS Code, Chrome DevTools, etc.)
        // Wait a moment then simulate Cmd+L to select line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.selectCurrentLine()
            
            // Then copy after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulateCopyCommand()
                
                // Check clipboard again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let newContents = pasteboard.string(forType: .string)
                    let newChangeCount = pasteboard.changeCount
                    
                    // If clipboard changed and has content, we captured the line
                    if newChangeCount != oldChangeCount, let capturedText = newContents, !capturedText.isEmpty {
                        // Restore original clipboard
                        if let oldContents = oldContents {
                            pasteboard.clearContents()
                            pasteboard.setString(oldContents, forType: .string)
                        }
                        
                        self.originalTextCache = capturedText
                        self.targetElement = nil
                        // Mark as false for isSelection since we captured the whole line
                        completion(.success((text: capturedText, isSelection: false)))
                        return
                    }
                    
                    // Retry once if first attempt failed
                    if attempt < 2 {
                        // Try again with longer delays
                        self.tryClipboardCapture(attempt: attempt + 1, completion: completion)
                        return
                    }
                    
                    // No text selected - restore clipboard and return error
                    if let oldContents = oldContents {
                        pasteboard.clearContents()
                        pasteboard.setString(oldContents, forType: .string)
                    }
                    
                    completion(.failure(.noSelection))
                }
            }
        }
    }
    
    private func selectCurrentLine() {
        // Use HID system state for reliable delivery
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let location = CGEventTapLocation.cghidEventTap
        
        // Create key events for Cmd+L (select line in many editors)
        // Key codes: 0x38 = Cmd, 0x25 = L
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: true),
              let lDown = CGEvent(keyboardEventSource: source, virtualKey: 0x25, keyDown: true),
              let lUp = CGEvent(keyboardEventSource: source, virtualKey: 0x25, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: false) else {
            return
        }
        
        // Set command flag on all events
        cmdDown.flags = .maskCommand
        lDown.flags = .maskCommand
        lUp.flags = .maskCommand
        cmdUp.flags = .maskCommand
        
        // Post events
        cmdDown.post(tap: location)
        lDown.post(tap: location)
        lUp.post(tap: location)
        cmdUp.post(tap: location)
    }
    
    private func simulateCopyCommand() {
        // Try using Accessibility to trigger Copy menu item first
        if triggerMenuItem(action: "copy:") {
            return
        }
        
        // Fallback to CGEvent if menu item fails
        performCGEventCopy()
    }
    
    private func simulatePasteCommand() {
        // Try using Accessibility to trigger Paste menu item first
        if triggerMenuItem(action: "paste:") {
            return
        }
        
        // Fallback to CGEvent if menu item fails
        performCGEventPaste()
    }
    
    private func triggerMenuItem(action: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Try to find the menu bar
        var menuBarValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        )
        
        guard result == .success, let menuBar = menuBarValue else {
            return false
        }
        
        // Try to find and trigger the menu item
        // This is a simplified approach - in practice, we'd need to traverse the menu hierarchy
        // For now, return false to fall back to CGEvent
        return false
    }
    
    private func performCGEventCopy() {
        // Use HID system state for reliable delivery to any app
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let location = CGEventTapLocation.cghidEventTap
        
        // Create key events for Cmd+C
        // Key codes: 0x38 = Cmd, 0x08 = C
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: false) else {
            return
        }
        
        // Set command flag on all events
        cmdDown.flags = .maskCommand
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        cmdUp.flags = .maskCommand
        
        // Post events with proper timing
        cmdDown.post(tap: location)
        cDown.post(tap: location)
        cUp.post(tap: location)
        cmdUp.post(tap: location)
    }
    
    private func performCGEventPaste() {
        // Use HID system state for reliable delivery
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let location = CGEventTapLocation.cghidEventTap
        
        // Create key events for Cmd+V
        // Key codes: 0x38 = Cmd, 0x09 = V
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: false) else {
            return
        }
        
        // Set command flag on all events
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = .maskCommand
        
        // Post events
        cmdDown.post(tap: location)
        vDown.post(tap: location)
        vUp.post(tap: location)
        cmdUp.post(tap: location)
    }
    
    /// Extracts the paragraph containing the given position
    private func extractParagraph(at position: Int, in text: String) -> String {
        let index = text.index(text.startIndex, offsetBy: min(position, text.count))
        
        // Find paragraph start (previous newline or start of text)
        var paragraphStart = text.startIndex
        if let lastNewline = text[..<index].lastIndex(of: "\n") {
            paragraphStart = text.index(after: lastNewline)
        }
        
        // Find paragraph end (next newline or end of text)
        var paragraphEnd = text.endIndex
        if let nextNewline = text[index...].firstIndex(of: "\n") {
            paragraphEnd = nextNewline
        }
        
        let paragraph = String(text[paragraphStart..<paragraphEnd])
        return paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Try to capture the current paragraph at cursor position when no text is selected
    /// Returns true if successful, false to continue to next fallback
    private func tryCaptureCurrentParagraph(element: AXUIElement, completion: @escaping (Result<(text: String, isSelection: Bool), TextCaptureError>) -> Void) -> Bool {
        // Get the full text value
        var valueResult: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueResult
        )
        
        guard result == .success,
              let fullText = valueResult as? String,
              !fullText.isEmpty else {
            return false
        }
        
        // Get the selected text range to find cursor position
        var rangeResult: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeResult
        )
        
        var cursorPosition = 0
        if rangeStatus == .success,
           let rangeValue = rangeResult,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
            cursorPosition = range.location
        }
        
        // Extract the paragraph at cursor position
        let paragraph = extractParagraph(at: cursorPosition, in: fullText)
        
        guard !paragraph.isEmpty else {
            return false
        }
        
        // Store the paragraph for replacement
        self.originalTextCache = paragraph
        
        // Mark that we captured the current paragraph (not a selection)
        // Return false for isSelection since we captured the whole paragraph
        completion(.success((text: paragraph, isSelection: false)))
        return true
    }
    
    /// Replaces the selected text with new content
    /// - Parameters:
    ///   - newText: The AI-generated text to insert
    ///   - completion: Callback with success or error
    func replaceSelectedText(with newText: String, completion: @escaping (Result<Void, TextCaptureError>) -> Void) {
        // If we used clipboard capture (targetElement is nil), use clipboard replacement
        guard let targetElement = targetElement else {
            performClipboardReplacement(with: newText) { success in
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(.replacementFailed))
                }
            }
            return
        }
        
        // Store current text for potential undo later
        if originalTextCache == nil {
            var currentValue: AnyObject?
            AXUIElementCopyAttributeValue(
                targetElement,
                kAXValueAttribute as CFString,
                &currentValue
            )
            originalTextCache = currentValue as? String
        }
        
        // Method 1: Try using the AXValue attribute
        let setValueResult = AXUIElementSetAttributeValue(
            targetElement,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )
        
        if setValueResult == .success {
            completion(.success(()))
            return
        }
        
        // Method 2: Try using selected text replacement
        let setSelectedResult = AXUIElementSetAttributeValue(
            targetElement,
            kAXSelectedTextAttribute as CFString,
            newText as CFTypeRef
        )
        
        if setSelectedResult == .success {
            completion(.success(()))
            return
        }
        
        // Method 3: Use clipboard-based replacement with paste command
        performClipboardReplacement(with: newText) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(.replacementFailed))
            }
        }
    }
    
    /// Restores the original text (undo functionality)
    /// - Parameter completion: Callback when undo is complete
    func undoLastReplacement(completion: @escaping (Bool) -> Void) {
        guard let originalText = originalTextCache,
              let targetElement = targetElement else {
            completion(false)
            return
        }
        
        let result = AXUIElementSetAttributeValue(
            targetElement,
            kAXValueAttribute as CFString,
            originalText as CFTypeRef
        )
        
        completion(result == .success)
    }
    
    /// Gets the screen position of the current text selection
    /// - Returns: NSPoint representing the selection position, or nil if unavailable
    func getSelectionPosition() -> NSPoint? {
        guard let targetElement = targetElement else { return nil }
        
        // Try to get the position of the selected text
        var positionValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            targetElement,
            kAXSelectedTextRangeAttribute as CFString,
            &positionValue
        )
        
        // Fallback: Get the position of the focused element
        var elementPosition: AnyObject?
        let posResult = AXUIElementCopyAttributeValue(
            targetElement,
            kAXPositionAttribute as CFString,
            &elementPosition
        )
        
        if posResult == .success,
           let pointValue = elementPosition,
           CFGetTypeID(pointValue) == AXValueGetTypeID() {
            var point = CGPoint.zero
            AXValueGetValue(pointValue as! AXValue, .cgPoint, &point)
            return NSPoint(x: point.x, y: point.y)
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Checks if the app has accessibility permissions
    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }
    
    /// Performs text replacement using clipboard paste method
    /// This is a fallback when direct accessibility replacement fails
    private func performClipboardReplacement(with text: String, completion: @escaping (Bool) -> Void) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Make sure target app is active before pasting
        NSApp.deactivate()
        
        // Simulate paste command after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePasteCommand()
            
            // Restore original clipboard content after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let oldContents = oldContents {
                    pasteboard.clearContents()
                    pasteboard.setString(oldContents, forType: .string)
                }
                completion(true)
            }
        }
    }
}
