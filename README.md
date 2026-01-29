# FocusHue

**FocusHue** is a minimalist macOS utility designed to curb digital addiction without the friction of "blocker" apps. Instead of locking you out of your device, FocusHue strips away the visual stimulation that makes distractions rewarding.

### The Why

Traditional productivity tools often fail because they treat focus like a physical barrier, abruptly cutting off digital coping mechanisms while leaving the underlying psychological urge for a break completely unmet. This creates a state of "unfocused work," where you remain at your desk but your brain is still actively hunting for a dopamine hit. FocusHue operates on the principle of **Incentive Salience**: by shifting the entire screen to greyscale, it systematically devalues the reward of distraction. When the vibrant, high-contrast UI elements designed to capture your attention—like red notification badges or colorful social feeds—are neutralized, they lose their neurological "sparkle." You aren't fighting your urges through willpower; you are simply making the distractions less interesting than the task at hand, allowing for a frictionless transition back to deep work.

---

## 🚀 Installation

### Option 1: The Standard Way (DMG)

1. Navigate to the [Releases](https://www.google.com/search?q=%23) tab of this repository.
2. Download the latest `FocusHue.dmg` file.
3. Open the DMG and **drag FocusHue to your Applications folder**.
4. **Right-click** the app in your Applications folder and select **Open** to bypass the initial macOS security verification.

### Option 2: The Terminal Way (Homebrew)

```bash
brew tap yourusername/tap
brew install --cask focushue

```

---

## 🛠 System Permissions: Why we need them

To function, FocusHue requires **Accessibility** or **Screen Recording** permissions within System Settings. Because macOS isolates application windows for security, a standard app cannot "reach out" and change the colors of other programs (like Chrome or Slack). By granting these permissions, you allow FocusHue to place an invisible, non-interactive mathematical filter over your entire display. This is the only way to ensure the greyscale effect remains persistent across all desktops, full-screen apps, and external monitors without affecting system performance.

---

## ⚡ Quick Features

* **Global Hotkey:** Instantly toggle greyscale on/off with a customizable shortcut.
* **Launch at Login:** Keep your focus environment ready from the moment you boot up.
* **Native Efficiency:** Built with Swift and Core Graphics for near-zero CPU and battery impact.

---

## 🔄 Alternatively

If you don't need a dedicated app or hotkey, macOS has a built-in greyscale filter. You can apply this manually by going to **System Settings > Accessibility > Display > Color Filters** and toggling "Greyscale" on. FocusHue simply exists to make this process instant and integrated into a high-performance productivity workflow.

---
