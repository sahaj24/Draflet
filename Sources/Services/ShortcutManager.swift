import Cocoa
import Carbon

// MARK: - ShortcutManager
/// Manages global keyboard shortcuts using Carbon Event Manager
/// Listens for Cmd+Shift+A (configurable) and triggers the AI assistant
class ShortcutManager {
    
    // MARK: - Properties
    
    /// Callback closure triggered when a shortcut is pressed.
    /// Parameter is the prompt ID for prompt shortcuts, or nil for default shortcut.
    var onShortcutTriggered: ((String?) -> Void)?
    
    /// Registered hotkeys keyed by Carbon hotkey ID
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    
    /// The event handler reference
    private var eventHandlerRef: EventHandlerRef?
    
    /// Current default shortcut configuration
    private var currentKeyCode: UInt32
    private var currentModifiers: UInt32
    private var promptShortcuts: [String: PromptShortcut] = [:]
    private var promptActionIdByHotKeyId: [UInt32: String] = [:]
    
    /// Reserved Carbon hotkey IDs
    private let defaultHotKeyId: UInt32 = 1
    private let firstPromptHotKeyId: UInt32 = 100
    
    // MARK: - Initialization
    
    init() {
        // Default: Cmd + Shift + A
        // Key code for 'A' is 0 (kVK_ANSI_A)
        self.currentKeyCode = UInt32(kVK_ANSI_A)
        self.currentModifiers = UInt32(cmdKey | shiftKey)
        
        setupEventHandler()
    }
    
    deinit {
        stopListening()
    }
    
    // MARK: - Public Methods
    
    /// Starts listening for the global keyboard shortcut
    func startListening() {
        registerAllHotKeys()
    }
    
    /// Stops listening for the global keyboard shortcut
    func stopListening() {
        unregisterAllHotKeys()
    }
    
    /// Updates the keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code (e.g., kVK_ANSI_A = 0)
    ///   - modifiers: Modifier flags (cmdKey, shiftKey, optionKey, controlKey)
    func updateShortcut(keyCode: Int, modifiers: [String]) {
        self.currentKeyCode = UInt32(keyCode)
        self.currentModifiers = buildModifierFlags(from: modifiers)
        registerAllHotKeys()
    }
    
    /// Updates prompt-specific shortcuts
    func updatePromptShortcuts(_ shortcuts: [String: PromptShortcut]) {
        self.promptShortcuts = shortcuts
        registerAllHotKeys()
    }
    
    /// Returns a human-readable description of the current shortcut
    func shortcutDescription() -> String {
        var description = ""
        
        if (currentModifiers & UInt32(cmdKey)) != 0 {
            description += "⌘"
        }
        if (currentModifiers & UInt32(shiftKey)) != 0 {
            description += "⇧"
        }
        if (currentModifiers & UInt32(optionKey)) != 0 {
            description += "⌥"
        }
        if (currentModifiers & UInt32(controlKey)) != 0 {
            description += "⌃"
        }
        
        // Convert key code to character
        let keyChar = keyCodeToCharacter(UInt32(currentKeyCode))
        description += keyChar.uppercased()
        
        return description
    }
    
    // MARK: - Private Methods
    
    /// Sets up the Carbon event handler
    private func setupEventHandler() {
        // Define the event specification for hotkey events
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        // Install the event handler
        let handlerUPP: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            
            // Get the hotkey ID from the event
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if result == noErr {
                DispatchQueue.main.async {
                    let promptId = manager.promptActionIdByHotKeyId[hotKeyID.id]
                    manager.onShortcutTriggered?(promptId)
                }
                return noErr // We handled this event
            }
            
            return OSStatus(eventNotHandledErr) // Let other apps handle this
        }
        
        InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerUPP,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
    
    /// Registers default and prompt hotkeys with the system
    private func registerAllHotKeys() {
        unregisterAllHotKeys()
        promptActionIdByHotKeyId.removeAll()
        
        _ = registerHotKey(
            keyCode: currentKeyCode,
            modifiers: currentModifiers,
            id: defaultHotKeyId
        )
        
        var nextPromptId = firstPromptHotKeyId
        var usedCombos: Set<String> = [comboFingerprint(keyCode: currentKeyCode, modifiers: currentModifiers)]
        
        for (promptId, shortcut) in promptShortcuts {
            let keyCode = UInt32(shortcut.keyCode)
            let modifiers = buildModifierFlags(from: shortcut.modifiers)
            let combo = comboFingerprint(keyCode: keyCode, modifiers: modifiers)
            
            // Skip invalid and duplicate combinations to keep registration stable.
            if modifiers == 0 || usedCombos.contains(combo) {
                continue
            }
            
            let hotKeyId = nextPromptId
            let didRegister = registerHotKey(
                keyCode: keyCode,
                modifiers: modifiers,
                id: hotKeyId
            )
            
            if didRegister {
                promptActionIdByHotKeyId[hotKeyId] = promptId
                usedCombos.insert(combo)
                nextPromptId += 1
            }
        }
    }
    
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(
            signature: OSType(fourCharCode("AIWA")),
            id: id
        )
        
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr, let hotKeyRef else {
            return false
        }
        
        hotKeyRefs[id] = hotKeyRef
        return true
    }
    
    /// Unregisters all hotkeys from the system
    private func unregisterAllHotKeys() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }
    
    private func buildModifierFlags(from modifiers: [String]) -> UInt32 {
        var result: UInt32 = 0
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd":
                result |= UInt32(cmdKey)
            case "shift":
                result |= UInt32(shiftKey)
            case "option", "alt":
                result |= UInt32(optionKey)
            case "control", "ctrl":
                result |= UInt32(controlKey)
            default:
                break
            }
        }
        return result
    }
    
    private func comboFingerprint(keyCode: UInt32, modifiers: UInt32) -> String {
        "\(modifiers)-\(keyCode)"
    }
    
    /// Converts a key code to its character representation
    private func keyCodeToCharacter(_ keyCode: UInt32) -> String {
        // Common key code mappings
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Escape): "Escape"
        ]
        
        return keyMap[keyCode] ?? "?"
    }
    
    /// Helper to convert 4-char string to OSType
    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        let chars = Array(string.utf8)
        for i in 0..<min(4, chars.count) {
            result = (result << 8) + UInt32(chars[i])
        }
        return result
    }
}

// MARK: - Key Code Constants
// Virtual key codes for reference
private let kVK_ANSI_A: Int = 0x00
private let kVK_ANSI_B: Int = 0x0B
private let kVK_ANSI_C: Int = 0x08
private let kVK_ANSI_D: Int = 0x02
private let kVK_ANSI_E: Int = 0x0E
private let kVK_ANSI_F: Int = 0x03
private let kVK_ANSI_G: Int = 0x05
private let kVK_ANSI_H: Int = 0x04
private let kVK_ANSI_I: Int = 0x22
private let kVK_ANSI_J: Int = 0x26
private let kVK_ANSI_K: Int = 0x28
private let kVK_ANSI_L: Int = 0x25
private let kVK_ANSI_M: Int = 0x2E
private let kVK_ANSI_N: Int = 0x2D
private let kVK_ANSI_O: Int = 0x1F
private let kVK_ANSI_P: Int = 0x23
private let kVK_ANSI_Q: Int = 0x0C
private let kVK_ANSI_R: Int = 0x0F
private let kVK_ANSI_S: Int = 0x01
private let kVK_ANSI_T: Int = 0x11
private let kVK_ANSI_U: Int = 0x20
private let kVK_ANSI_V: Int = 0x09
private let kVK_ANSI_W: Int = 0x0D
private let kVK_ANSI_X: Int = 0x07
private let kVK_ANSI_Y: Int = 0x10
private let kVK_ANSI_Z: Int = 0x06
private let kVK_Space: Int = 0x31
private let kVK_Return: Int = 0x24
private let kVK_Tab: Int = 0x30
private let kVK_Escape: Int = 0x35
