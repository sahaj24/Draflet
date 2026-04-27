#!/bin/bash
set -x
cd /Users/sahaj/Desktop/mac2/AIWritingAssistant

# Kill old processes
pkill -9 -f AIWritingAssistant || true
pkill -9 -f swift || true
sleep 2

# Fully delete old app from system and reset permissions
rm -rf "/Applications/AIWritingAssistant.app"
rm -rf "$HOME/Applications/AIWritingAssistant.app"
tccutil reset Accessibility com.aiwritingassistant.app 2>/dev/null || true
echo "Old app and permissions fully removed from system"

# Clean
rm -rf .build build
swift package clean

# Build
echo "Starting build..."
swift build -c release 2>&1
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "BUILD SUCCESS"
    
    # Create app bundle
    mkdir -p build/AIWritingAssistant.app/Contents/MacOS
    mkdir -p build/AIWritingAssistant.app/Contents/Resources
    
    cp .build/release/AIWritingAssistant build/AIWritingAssistant.app/Contents/MacOS/
    
    # Create Info.plist
    cat > build/AIWritingAssistant.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AIWritingAssistant</string>
    <key>CFBundleIdentifier</key>
    <string>com.aiwritingassistant.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.aiwritingassistant.auth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>aiwriting</string>
            </array>
        </dict>
    </array>
    <key>CFBundleName</key>
    <string>AI Writing Assistant</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>AI Writing Assistant needs accessibility access to read and replace text.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF
    
    # Copy to /Applications
    cp -R build/AIWritingAssistant.app /Applications/
    echo "App installed to /Applications"
    
    echo "App bundle created at:"
    ls -lh build/AIWritingAssistant.app/Contents/MacOS/AIWritingAssistant
    
    # Start app
    open /Applications/AIWritingAssistant.app
    echo "App started!"
else
    echo "BUILD FAILED with status $BUILD_STATUS"
fi
