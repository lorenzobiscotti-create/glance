# Glance — setup on the Mac

Glance is a menu bar app that looks like the clock. Press **⌥⇧Space** (Option + Shift + Space), drag a box over anything on screen, and the answer shows in the menu bar for a few seconds. Click it to see the full answer.

Needs macOS 14 (Sonoma) or newer.

## 1. Get the files onto the Mac

Copy the `Glance/Glance` folder (the 6 `.swift` files) to the Mac — OneDrive, a USB stick or AirDrop all work.

## 2. Make the Xcode project

1. Install **Xcode** from the Mac App Store and open it.
2. **File → New → Project… → macOS → App**.
3. Product Name: `Glance`. Interface: **SwiftUI**. Language: **Swift**. Turn off tests/Core Data if offered.
4. In the project's left sidebar, delete `ContentView.swift` (Move to Trash).
5. Drag the 6 `.swift` files into the `Glance` folder in the sidebar. When asked, tick **Copy items if needed** and **Replace** for `GlanceApp.swift`.

## 3. Settings (click the blue Glance project at the top of the sidebar → the Glance target)

- **General → Minimum Deployments:** macOS **14.0**.
- **Info → Custom macOS Application Target Properties:** hover any row, click **+**, choose **Application is agent (UIElement)**, set it to **YES**. This hides the Dock icon.
- **Signing & Capabilities:**
  - Team: pick your Apple ID (Personal Team is fine).
  - Under **App Sandbox**, tick **Outgoing Connections (Client)** so it can reach the API.

## 4. Run it

1. Press **⌘R**. The time appears in the menu bar and it asks for your API key (get one at console.anthropic.com → API Keys). The key is saved in your Keychain.
2. The first time, macOS asks for **Screen Recording** permission. Turn Glance on in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit Glance (click it → Quit) and press ⌘R again.

## 5. Make it look like the real clock

- **System Settings → Control Center → Clock Options → Style: Analog.** The real clock becomes a small icon.
- Hold **⌘** and drag Glance's time to wherever you want it in the menu bar.

## Using it

- **⌥⇧Space**, then drag a box. **Esc** or right-click cancels.
- A small `·` after the time means it's thinking.
- The short answer shows for 6 seconds, then the time comes back.
- Click the time to see the full answer and a **Copy Answer** button.

## Changing things

| What | Where |
| --- | --- |
| How long the answer shows | `answerSeconds` in `MenuBarClock.swift` |
| Max length in the menu bar | `maxChars` in `MenuBarClock.swift` |
| Shortcut | `HotKey(...)` line in `GlanceApp.swift` |
| What it answers and how | `systemPrompt` in `ClaudeClient.swift` |
| Model / speed | `model` and `effort` in `ClaudeClient.swift` |

Cost: roughly 1–2 cents per question with the default model (Claude Opus 5.5 at low effort).

If Xcode shows build errors, copy them and paste them back to Claude.
