# Vaultlyn

## Overview

Vaultlyn is a modern macOS password‑vault application built with **SwiftUI** and **SwiftData**. It provides secure vault management with a premium, dark‑themed UI that features glass‑morphism effects, vibrant accent colours, and smooth micro‑animations.

Key privacy features include:

- **AES‑256‑GCM encryption** with PBKDF2‑derived keys.
- **Decoy Mode** – a secondary hidden vault accessed with a decoy password.
- **Stealth Filenames** – on‑disk filenames are obfuscated when the vault is locked.
- **Emoji personalization** – each vault can be represented by an emoji icon.
- **Recovery key** generation for emergency access.

The app integrates tightly with macOS Finder/Dock, supports drag‑and‑drop import of files, and provides a polished, responsive experience.

## Features

- Secure encrypted vaults with master password protection.
- Optional decoy password for hidden access.
- Stealth‑mode filenames that hide content when locked.
- Emoji‑based vault icons for quick visual identification.
- Automatic session persistence and auto‑unlock on launch.
- Recovery key generation and verification.
- Dark‑mode UI with glass‑morphism panels and subtle hover animations.
- Full macOS menu integration (About, New Vault, Lock, Refresh, etc.).
- Keyboard shortcuts for common actions.

## Screenshot

![Vaultlyn UI Mockup](file:///Users/sidharth/.gemini/antigravity/brain/14e8ec6b-722d-47a8-88c0-cac7169c6e96/vaultlyn_mockup_1777818407709.png)

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/Vaultlyn.git
   cd Vaultlyn
   ```
2. **Open the Xcode project**
   ```bash
   open Vaultlyn.xcodeproj
   ```
3. Build and run the app on macOS 13+ (requires Xcode 15 or later).

## Usage

- Click the **"Add Vault"** button in the sidebar to create a new vault.
- Choose an emoji, name, master password, and optionally enable **Decoy** or **Stealth**.
- Drag files onto the vault view to import them.
- Use the **File** menu to lock/unlock, refresh, or change the password.
- If you lose your master password, use the **Recovery Key** generated during vault creation.

## Development

- **Language:** Swift 5.9
- **Frameworks:** SwiftUI, SwiftData, CryptoKit, CommonCrypto
- **No external dependencies** – all cryptographic primitives are native.

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/awesome-feature`).
3. Ensure code follows the existing style and passes `swift build`.
4. Open a pull request describing your changes.

## License

MIT License – see the [LICENSE](LICENSE) file for details.
