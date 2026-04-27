# Draflet for macOS

Draflet is a menu bar writing assistant for macOS. You can highlight text in almost any app, run a shortcut, and rewrite that text without leaving your current window.

The app is built with SwiftUI and uses macOS accessibility APIs for text capture and replacement. It includes a floating action panel, account based authentication, onboarding, usage tracking, and token based limits.

## Environment setup

Set these values on your machine before launching the app.

```bash
export DRAFLET_SUPABASE_ANON_KEY="your_supabase_anon_key"
export DRAFLET_SUPABASE_URL="https://your-project.supabase.co"
export DRAFLET_PROXY_BASE_URL="https://your-worker-url.workers.dev"
```

The code checks these names first and also accepts SUPABASE_ANON_KEY, SUPABASE_URL, and PROXY_BASE_URL.

## How to run it

Open this folder in Xcode and run the app target.

You can also build from Terminal.

```bash
swift build
```

When the app launches for the first time, grant accessibility permission in System Settings so Draflet can read and replace selected text.

## Current structure

`Sources/AIWritingAssistantApp.swift` contains app startup and window routing.

`Sources/Services` contains auth, AI calls, shortcut handling, text capture, token management, and persistence logic.

`Sources/UI` contains login, onboarding, floating action panel, and settings views.

## Notes

This project is active and the UI is still evolving. The focus right now is a smooth login flow, stable onboarding, and fast text rewrite actions from anywhere on the desktop.
