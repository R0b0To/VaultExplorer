# VaultExplorer OEM Background Service & Automation Setup Guide

Aggressive OEM Android task killers (e.g. Samsung One UI, Xiaomi MIUI/HyperOS, OnePlus/Oppo ColorOS) frequently terminate background foreground services, purge active cryptographic session keys from memory, and drop headless broadcast intents when the app is backgrounded or swiped from the Recents list.

Follow these OEM-specific configuration steps to ensure persistent vault keep-alive and reliable offline automation.

---

## 1. Samsung One UI (Android 13, 14, 15+)

Samsung's "Sleeping Apps" and "Device Care" subsystems aggressively stop background services unless VaultExplorer is explicitly exempted.

### Step 1: Set Battery Usage to Unrestricted
1. Open **Settings** ➔ **Apps** ➔ **VaultExplorer**.
2. Tap **Battery**.
3. Select **Unrestricted** (Default is usually *Optimized*).

### Step 2: Disable Automatic App Hibernation
1. In the same **Apps** ➔ **VaultExplorer** screen:
2. Toggle **Pause app activity if unused** to **OFF**.

### Step 3: Prevent Addition to Sleeping Apps List
1. Open **Settings** ➔ **Battery** (or **Device Care** ➔ **Battery**).
2. Tap **Background usage limits**.
3. Ensure **Put unused apps to sleep** does NOT contain VaultExplorer.
4. Tap **Never sleeping apps**, tap **+**, and add **VaultExplorer**.

### Step 4: Lock in Recents (Optional but Recommended)
1. Open **VaultExplorer** and swipe up to the **Recents** screen.
2. Tap the **VaultExplorer** app icon above its thumbnail card.
3. Tap **Lock this app** (shows a padlock icon).

---

## 2. Xiaomi MIUI / HyperOS

Xiaomi devices enforce aggressive background limits through the separate **Security** app.

### Step 1: Enable Autostart
1. Open **Settings** ➔ **Apps** ➔ **Permissions** ➔ **Autostart** (or **Manage apps** ➔ **VaultExplorer** ➔ **Autostart**).
2. Toggle **Autostart** to **ON**.
3. If prompted, allow secondary launch / launch by other apps.

### Step 2: Set Battery Saver to No Restrictions
1. Open **Settings** ➔ **Apps** ➔ **Manage apps** ➔ **VaultExplorer**.
2. Scroll to **Battery saver**.
3. Select **No restrictions** (removes MIUI's custom background killer).

### Step 3: Disable App Hibernation
1. In **Manage apps** ➔ **VaultExplorer**, turn off **Pause app activity if unused**.

### Step 4: Lock App in Recents
1. Open the **Recents** screen.
2. Long-press the **VaultExplorer** card and tap the **Padlock icon**.

---

## 3. OnePlus / Oppo / Realme (OxygenOS / ColorOS)

### Step 1: App Battery Management
1. Open **Settings** ➔ **Battery** ➔ **More settings** ➔ **App battery management**.
2. Tap **VaultExplorer**.
3. Enable **Allow background activity** and **Allow auto-launch**.

### Step 2: Disable Battery Optimization
1. Open **Settings** ➔ **Battery** ➔ **More settings** ➔ **Optimize battery use**.
2. Find **VaultExplorer** and choose **Don't optimize**.

### Step 3: App Hibernation
1. Open **Settings** ➔ **Apps** ➔ **App management** ➔ **VaultExplorer**.
2. Turn off **Pause app activity if unused**.

---

## 4. Google Pixel / Motorola / Sony (Stock Android)

Stock Android adheres to standard Android foreground service contracts, but adaptive battery can still delay or suppress alarms and broadcasts when battery is low.

### Step 1: Battery Optimization
1. Open **Settings** ➔ **Apps** ➔ **See all apps** ➔ **VaultExplorer**.
2. Tap **App battery usage** (or **Battery**).
3. Select **Unrestricted**.

### Step 2: App Hibernation
1. In **Settings** ➔ **Apps** ➔ **VaultExplorer**:
2. Toggle **Pause app activity if unused** to **OFF**.

---

## 5. Summary Checklist for Automation Users

Before running unattended Tasker / MacroDroid / Termux automation chains:
- [ ] Battery set to **Unrestricted** / **No restrictions**.
- [ ] **Pause app activity if unused** toggled **OFF**.
- [ ] App whitelisted from OEM "Sleeping Apps" or memory cleaners.
- [ ] Stored automation password set in Vault Settings if unlocking headlessly.
- [ ] For camera automation (`TAKE_PHOTO`, `START_RECORDING`), **Allow camera capture** enabled and camera permissions granted once in UI.
