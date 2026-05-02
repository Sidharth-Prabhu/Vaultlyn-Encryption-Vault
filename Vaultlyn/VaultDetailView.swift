import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct VaultDetailView: View {
    let vault: Vault
    @State private var vaultManager = VaultManager.shared
    @State private var password = ""
    @State private var error: String?
    @State private var selectedItem: VaultItem?
    @State private var previewURL: URL?
    @State private var searchText = ""
    
    // Get the specific session for this vault
    private var session: VaultSession {
        vaultManager.session(for: vault)
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 20)
    ]
    
    var filteredItems: [VaultItem] {
        if searchText.isEmpty {
            return session.unlockedItems
        } else {
            return session.unlockedItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        ZStack {
            if session.isUnlocked {
                unlockedView
            } else if session.isProcessing {
                processingView
            } else {
                lockedView
            }
        }
        .navigationTitle(vault.name)
        .toolbar {
            if session.isUnlocked {
                ToolbarItem {
                    Button(action: { 
                        Task { @MainActor in
                            await vaultManager.lock(vault: vault)
                        }
                    }) {
                        Label("Lock", systemImage: "lock.fill")
                    }
                }
            }
        }
        .quickLookPreview($previewURL)
    }
    
    var unlockedView: some View {
        ScrollView {
            if session.unlockedItems.isEmpty {
                emptyVaultView
            } else if filteredItems.isEmpty {
                noSearchResultsView
            } else {
                fileGridView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search files...")
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls: urls)
            return true
        }
        .onKeyPress(.space) {
            if let selected = selectedItem {
                previewURL = selected.url
                return .handled
            }
            return .ignored
        }
    }
    
    private var emptyVaultView: some View {
        ContentUnavailableView(
            "No Files Yet",
            systemImage: "doc.badge.plus",
            description: Text("Drag and drop files here to add them to the vault.")
        )
        .frame(minHeight: 400)
    }
    
    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(minHeight: 400)
    }
    
    private var fileGridView: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(filteredItems) { item in
                FileGridView(item: item, isSelected: selectedItem?.id == item.id)
                    .onTapGesture {
                        selectedItem = item
                    }
                    .onTapGesture(count: 2) {
                        previewURL = item.url
                    }
                    .contextMenu {
                        Button {
                            previewURL = item.url
                        } label: {
                            Label("Quick Look", systemImage: "eye")
                        }
                        
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        
                        Divider()
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.url.path, forType: .string)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding()
    }
    
    var lockedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Unlock \(vault.name)")
                .font(.title2)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit { unlock() }
            
            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Button("Unlock Vault") {
                unlock()
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || session.isProcessing)
        }
        .padding()
    }
    
    var processingView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                    Text(session.isUnlocked ? "Securing Vault..." : "Unlocking Vault...")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(session.progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(value: session.progress)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(height: 4)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.logs.indices, id: \.self) { index in
                            Text(session.logs[index])
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(session.logs[index].contains("ERROR") ? .red : .green.opacity(0.8))
                                .id(index)
                        }
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.8))
                .onChange(of: session.logs.count) { _, _ in
                    if let lastIndex = session.logs.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: 500, maxHeight: 350)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(radius: 20)
    }
    
    private func unlock() {
        error = nil
        let currentPassword = password
        Task { @MainActor in
            do {
                try await vaultManager.unlock(vault: vault, password: currentPassword)
                password = ""
            } catch {
                self.error = "Invalid password or corrupted vault."
            }
        }
    }
    
    private func handleDrop(urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                try? await vaultManager.encryptFile(at: url, session: session)
            }
        }
    }
    
    private func deleteItem(_ item: VaultItem) {
        try? FileManager.default.removeItem(at: item.url)
        try? vaultManager.refreshItems(session: session)
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
    }
}

struct FileGridView: View {
    let item: VaultItem
    let isSelected: Bool
    
    var body: some View {
        VStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
            
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(4)
        }
        .frame(width: 100)
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}
