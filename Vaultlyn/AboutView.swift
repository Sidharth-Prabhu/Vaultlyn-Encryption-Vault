import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // App Logo & Name
            VStack(spacing: 12) {
                // Using the Logo from Assets.xcassets
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                
                Text("Vaultlyn")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                Text("Version 1.0 (Build 100)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            
            // Description
            Text("Vaultlyn is a premium, secure file vault designed for macOS. It uses industry-standard AES-256-GCM encryption and PBKDF2 key derivation to keep your sensitive data safe and accessible only to you.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .foregroundStyle(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Links & Credits
            VStack(spacing: 16) {
                Link(destination: URL(string: "https://vaultlyn.app")!) {
                    Label("Visit Website", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                VStack(spacing: 4) {
                    Text("Developed by Sidharth P L")
                        .font(.headline)
                    
                    Link("Contact Developer", destination: URL(string: "mailto:contact@sidharthpl.com")!)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 450)
        .background(.ultraThinMaterial)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}
