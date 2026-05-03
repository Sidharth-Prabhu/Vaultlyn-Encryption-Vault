# Project Overview: Vaultlyn

Vaultlyn is a premium, enterprise-grade file vault application designed specifically for macOS. It provides users with a secure, intuitive, and high-performance solution for protecting sensitive data using industry-standard encryption protocols.

## Tagline
**"Your Privacy, Reimagined. Secure. Stealthy. Personal."**

---

## Core Features

### 🔐 Enterprise-Grade Security
- **AES-256-GCM Encryption**: Uses the strongest available symmetric encryption for all files.
- **PBKDF2 Key Derivation**: Ensures passwords are computationally expensive to crack.
- **Secure Keychain Integration**: Optionally store master passwords in the macOS Keychain for seamless access.

### 🕵️ Plausible Deniability (Decoy Mode)
- **Secondary Password**: Users can set a "Decoy Password" that opens a completely different, hidden storage area.
- **Hidden Access**: If forced to reveal a password, users can provide the decoy, which reveals non-sensitive data while keeping the master vault hidden.

### 🌫️ Stealth Filenames
- **Metadata Obfuscation**: When enabled, Vaultlyn replaces real filenames with randomized UUIDs on disk.
- **Zero-Knowledge filenames**: Even if the encrypted files are accessed, the attacker cannot discern the nature of the content from the filenames.

### 🛡️ Brute Force & Recovery
- **Protection**: Monitors failed login attempts and implements lockouts to prevent automated attacks.
- **Recovery Key**: Generates a unique `.vaultkey` file during creation, which is the only way to regain access if a password is forgotten.

### ✨ Premium UX & Personalization
- **Emoji Customization**: Users can personalize each vault with a unique emoji icon.
- **Native macOS Experience**: Built with SwiftUI, offering a sleek, modern, and native look and feel with support for Dark Mode and glassmorphism.
- **Drag-and-Drop**: Easy file importing via system-wide drag-and-drop or dock-drop support.

---

## Technical Specifications
- **Platform**: macOS (built for Apple Silicon and Intel).
- **Language**: Swift.
- **Frameworks**: SwiftUI (UI), SwiftData (Persistence).
- **Encryption**: CryptoKit / AES-256-GCM.
- **Security**: Security-scoped bookmarks for sandboxed folder access.

---

## Brand Identity: Frissco Creative Labs
Vaultlyn is developed by **Frissco Creative Labs**. The brand identity focuses on:
- **Premium Aesthetics**: High-end typography (Inter/Outfit), smooth gradients, and subtle micro-animations.
- **Security & Trust**: A clean, "locked-down" yet approachable design language.
- **Professionalism**: Targeted at professionals, researchers, and privacy-conscious individuals.

---

## Website Requirements for LLM
When building the landing page for Vaultlyn, the following should be prioritized:

### 1. Visual Style
- **Aesthetic**: Premium, dark-themed (with light mode option), utilizing glassmorphism and modern gradients.
- **Imagery**: High-quality mockups of the Vaultlyn UI (Sidebar, Encryption progress, Decoy toggle).
- **Typography**: Modern, clean sans-serif (e.g., Roboto, Inter).

### 2. Key Sections
- **Hero**: Impactful headline, subheadline, and a "Download Now" primary CTA.
- **Feature Grid**: Detailed cards for AES-256, Decoy Mode, Stealth Mode, and Brute Force Protection.
- **UX Showcase**: Visual representation of the personalized vaults and emoji support.
- **Security Deep Dive**: A section explaining the technical robustness (PBKDF2, GCM).
- **Footer**: Branding (Frissco Creative Labs), Support email, and links.

### 3. Messaging
- Focus on "Total Privacy" and "User Control".
- Highlight the "Plausible Deniability" aspect as a unique selling point.
- Emphasize the "Native macOS" performance and integration.

---

## Contact & Resources
- **Developer**: Frissco Creative Labs
- **Website**: [vaultlyn.frissco.net](https://vaultlyn.frissco.net)
- **Support**: [thefrisscoteamofficial@gmail.com](mailto:thefrisscoteamofficial@gmail.com)
- **Documentation**: [vaultlyn.com/docs](https://vaultlyn.com/docs)
