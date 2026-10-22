<h1 align="center">GlassOTP</h1>

<p align="center">
  A lightweight <b>TOTP authenticator for macOS</b> that lives in your menu bar.<br>
  Your one-time codes in a second — no full window, no clutter, fully offline.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-11.7%2B-black?style=flat-square&logo=apple" alt="macOS 11.7+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-555?style=flat-square" alt="Universal">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <img src="screenshots/main.png" width="452" alt="GlassOTP token list">
</p>

## Contents

- [Features](#features)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Everyday use](#everyday-use)
- [Adding tokens](#adding-tokens)
- [Managing tokens](#managing-tokens)
- [Menu bar menu & settings](#menu-bar-menu--settings)
- [Backup & restore](#backup--restore)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Notes & limitations](#notes--limitations)
- [Building from source](#building-from-source)

## Features

**Fast**

- Lives in the menu bar — no Dock icon, one click or **⌥⌘O** away
- Click a row to copy its code; codes are grouped (`123 456`) for easy reading
- **Next code** appears in the last seconds of a period — copy it without waiting
- **Keyboard-first**: type to search, **↑/↓** to select, **Enter** to copy and jump back to your app

**Flexible import**

- `otpauth://totp/…` links and **Google Authenticator** exports (`otpauth-migration://…`)
- QR codes from an image file, drag & drop, the clipboard or the **camera**
- Manual entry — SHA1 / SHA256 / SHA512, 6 or 8 digits, any period

**Private & secure**

- Secrets stored in the **macOS Keychain**, never in plain text on disk
- Optional **Touch ID / password lock** for the whole list
- Touch ID required to show secrets and QR codes, export a backup or delete everything
- Encrypted, password-protected backups
- **No network connections** — nothing is synced, sent or uploaded

**Comfortable**

- Pin, rename and search tokens
- Close after copy, copy sound, launch at login — all optional

## Installation

1. Download the release archive and extract it.
2. Move `GlassOTP.app` into your **Applications** folder.
3. Open it — the key icon appears in the menu bar.

### First launch (Gatekeeper)

GlassOTP is not distributed with an Apple Developer certificate, so macOS may block the first launch or say:

> "The application is damaged and can't be opened. You should move it to the Trash."

This is the quarantine flag macOS adds to downloaded files, not actual damage. Run once in Terminal:

```sh
xattr -r -c /Applications/GlassOTP.app
```

Then open the app normally (or Control-click → **Open** the first time).

Optional third-party helpers (not bundled with GlassOTP):

- [Sentinel](https://github.com/alienator88/Sentinel) — removes the `com.apple.quarantine` attribute (macOS 13+).
- AutoFix — clears quarantine attributes and fixes permissions on older systems.

## Getting started

Click the key icon in the menu bar (or press **⌥⌘O**). The list is empty at first — press **+** to add your first token.

<p align="center">
  <img src="screenshots/empty.png" width="400" alt="Empty token list">
</p>

## Everyday use

### Copy a code

Click any row to copy its current code. A countdown ring shows how long the code stays valid; it turns orange and red near the end.

<p align="center">
  <img src="screenshots/list.png" width="400" alt="Token list">
</p>

### Next code

In the last **5 seconds** of a period, the next code appears next to the current one. Click it to copy it right away instead of waiting for the countdown — most services also accept the neighbouring code. When the period rolls over, the next code slides into place.

<p align="center">
  <img src="screenshots/next-code.png" width="452" alt="Next code next to the current one">
</p>

### Keyboard

| Key | Action |
| --- | --- |
| **⌥⌘O** | Open or close GlassOTP from any app |
| *type* | Search — the first match is selected |
| **↑ / ↓** | Move the selection |
| **Enter** | Copy the selected code, close the window and return to the app you came from — ready for **⌘V** |

A pinned window stays open after **Enter**. The shortcut can be turned off in [settings](#menu-bar-menu--settings) if it conflicts with another app.

<p align="center">
  <img src="screenshots/keyboard.png" width="400" alt="Keyboard search with a selected row">
</p>

## Adding tokens

Press **+** in the top-right corner of the list to open the **Add Token** window.

### Link / QR

- **Drop** an image with a QR code onto the window, or click **Choose Image…**
- **Paste** takes whatever is on the clipboard: an `otpauth://` link, a copied image or an image file copied in Finder.
- **Scan with Camera** works with any camera: the built-in one, an iPhone (Continuity Camera, macOS 14+) or a virtual camera such as OBS.
- Or type a link into the **Link** field — `otpauth://totp/…` or a Google Authenticator export (`otpauth-migration://…`, many tokens at once).

<p align="center">
  <img src="screenshots/add-link.png" width="420" alt="Add token — Link / QR">
  <img src="screenshots/camera.png" width="420" alt="Scanning a QR code with the camera">
</p>

### Manually

Enter the issuer and/or account and the Base32 secret. Change digits (6 or 8), period and algorithm (SHA1 / SHA256 / SHA512) only if the service says so.

<p align="center">
  <img src="screenshots/add-manual.png" width="420" alt="Add token — Manually">
</p>

Press **Add**. The window stays open, so you can add several tokens in a row; **Close** or **Esc** closes it.

- Tokens that already exist are skipped.
- Entries GlassOTP can't generate codes for (HOTP or MD5 in a Google Authenticator export) are skipped and counted in the result message.
- A token needs a name: an issuer, an account, or both.

## Managing tokens

Right-click a token:

- **Pin / Unpin** — keep important tokens at the top; unpinning puts a token back where it was
- **Rename…** — change the issuer or account
- **Show QR code** — move the token to another authenticator *(requires Touch ID / password)*
- **Show / edit secret…** — view or replace the Base32 secret *(requires Touch ID / password)*
- **Delete** — remove the token and its secret from the Keychain

<p align="center">
  <img src="screenshots/token-menu.png" width="400" alt="Token context menu">
  <img src="screenshots/qr.png" width="400" alt="Token QR code">
</p>

## Menu bar menu & settings

**Right-click** the key icon for the quick menu:

- **Open** — show the token list
- **Export / Import** — [backup & restore](#backup--restore)
- **Delete All** — remove every token and reset the secret storage *(requires Touch ID / password)*
- **Pin popover** — keep the list open when you click elsewhere
- **Launch at login** — start GlassOTP when you log in. Enable it from the copy in **Applications**; if you move the app, turn it on again, and turn it off before deleting the app.
- **Exit**

The **settings menu** (slider icon in the list):

- **Close after copy** — close the list shortly after copying (a pinned list stays open)
- **Play sound on copy**
- **Global shortcut ⌥⌘O**
- **Require Touch ID to view** — lock the list until you authenticate

<p align="center">
  <img src="screenshots/menu.png" width="380" alt="Menu bar menu">
  <img src="screenshots/settings.png" width="430" alt="Settings menu">
</p>

## Backup & restore

From the right-click menu:

- **Export** — authenticate, choose a location, set a password and save an encrypted `.glassotp` file with all tokens. GlassOTP warns you if the password is shorter than 8 characters.
- **Import** — select a `.glassotp` file and enter its password. New tokens are added, existing ones are skipped.

> The backup file contains all your secrets. Choose a strong password and keep the file somewhere safe.

## Security

- Token secrets live in the **macOS Keychain**, never as plain text on disk.
- GlassOTP makes **no network connections** — all data stays on your Mac.
- **Touch ID** or your macOS password is required to view or edit a secret, show a QR code, export a backup and delete all tokens. Authentication is remembered for a short time to avoid repeated prompts.
- **Require Touch ID to view** hides all codes until you authenticate, every time the list opens.
- Backups are encrypted with **AES-GCM** using a key derived from your password (**PBKDF2-HMAC-SHA256**). Without the password, a backup can't be read.
- Copied codes are marked as sensitive, so well-behaved clipboard managers don't store them.

<p align="center">
  <img src="screenshots/locked.png" width="400" alt="Locked token list">
</p>

## Troubleshooting

| Message in the list | What to do |
| --- | --- |
| **No access to the Keychain** | You declined the Keychain password prompt. Click **Retry** and allow access. |
| **Secret storage is damaged** | Use **Delete All** in the right-click menu, then **Import** a backup. The damaged data is kept aside in the Keychain, not destroyed. |
| **Some saved tokens couldn't be read** | Restore the missing tokens from a backup with **Import**. |
| **Notifications are off** | Export / import / delete confirmations won't appear as notifications. Import errors are still shown as a dialog. |

- **⌥⌘O does nothing** — another app may already use this shortcut. Turn off **Global shortcut ⌥⌘O** in settings and use the menu bar icon instead.

## Notes & limitations

- **TOTP only** (time-based codes). HOTP (counter-based) tokens are not supported.
- Codes are **6 or 8 digits**.

## Building from source

Requirements: **Xcode 14+**, **Swift 5.7+**.

```sh
git clone https://github.com/Croakieee/GlassOTP.git
cd GlassOTP
open GlassOTP.xcodeproj
```

Build and run the **GlassOTP** scheme.

## Contributing

Pull requests and improvements are welcome.
If you find a bug or have a feature request, please open an issue.

## Disclaimer

GlassOTP is an open source project provided without warranty. Use it at your own risk.
For maximum security, always keep recovery/backup codes for your accounts.

Released under the [MIT License](LICENSE).

## ☕ Support the Project

If you like this project and want to support its development, you can buy me a coffee using **USDT (TRC20)**.

<div align="center">

<a href="https://tronscan.org/#/address/TKy58zzJkoTzab3XZXE5YpZVpH3oRoghjg">
  <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-USDT%20(TRC20)-ff813f?style=for-the-badge&logo=buymeacoffee&logoColor=white" />
</a>

</div>

<p align="center">

**USDT (TRC20) Wallet**

`TKy58zzJkoTzab3XZXE5YpZVpH3oRoghjg`

</p>

---

⭐ Any support helps keep the project improving and maintained.
