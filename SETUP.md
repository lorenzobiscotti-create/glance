# Glance

A menu bar clock that answers screenshots. Needs macOS 14 (Sonoma) or newer.

**Download:** https://github.com/lorenzobiscotti-create/glance/releases/latest/download/Glance.zip

## Install (once)

1. Download the zip above, double-click it, and drag **Glance** into **Applications**.
2. Open Glance. macOS says it can't check it. Click **Done**, go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Copy your API key (from console.anthropic.com → API Keys). Glance saves it by itself
   and shows **✓ API key works**.
4. **System Settings → Control Center → Clock Options → Style: Analog.**
   Hold ⌘ and drag Glance's time where you want it.

Glance updates itself after that. It checks every 30 minutes and when the Mac wakes; click the time →
**Check for Updates** to check now.

## Use

1. Tap **⌘ twice** quickly. Glance screenshots your whole screen and Claude answers the
   question on it (if you highlighted something, it answers that).
   The first time, macOS asks to let Glance use Accessibility (so it can take the screenshot):
   click **Open System Settings** and turn **Glance** on.
   To pick out one spot instead, press **⌃⇧⌘4** (Control + Shift + Command + 4) and drag a box.
2. A small `·` after the time means it's thinking.
3. The answer replaces the time for 6 seconds (press **⌥ Option** to hide it sooner).
   Click the time to see all of it.

Turn **Answer Screenshots** off in Glance's menu to pause it.
To change the key, copy the new one and click **Use Copied API Key**.
Cost: about 1–2 cents per answer.
