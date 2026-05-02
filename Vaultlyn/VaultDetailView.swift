import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct VaultDetailView: View {
    let vault: Vault
    @State private var vaultManager = VaultManager.shared
    @State private var password = ""
    @State private var error: String?
    @State private var selection: Set<UUID> = []
    @State private var previewURL: URL?
    @State private var searchText = ""
    
    // Navigation state
    @State private var navigationStack: [URL] = []
    
    // Marquee selection state
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var itemFrames: [UUID: CGRect] = [:]
    
    private var session: VaultSession {
        vaultManager.session(for: vault)
    }
    
    private var currentFolderURL: URL {
        navigationStack.last ?? session.scopedURL ?? URL(fileURLWithPath: vault.rootPath)
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
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if session.isUnlocked {
                    breadcrumbBar
                    Divider()
                    unlockedView
                } else if session.isProcessing {
                    processingView
                } else {
                    lockedView
                }
            }
            
            // Marquee Rect
            if let start = dragStart, let end = dragEnd {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .border(Color.accentColor.opacity(0.5), width: 1)
                    .frame(
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    .offset(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y)
                    )
            }
        }
        .navigationTitle(vault.name)
        .toolbar {
            if session.isUnlocked {
                ToolbarItem(placement: .navigation) {
                    Button {
                        if !navigationStack.isEmpty {
                            navigationStack.removeLast()
                            try? vaultManager.refreshItems(session: session, at: currentFolderURL)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(navigationStack.isEmpty)
                }
                
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
        .onChange(of: vault) { _, _ in
            navigationStack = []
            if session.isUnlocked {
                try? vaultManager.refreshItems(session: session, at: currentFolderURL)
            }
        }
    }
    
    var breadcrumbBar: some View {
        HStack {
            Button {
                navigationStack = []
                try? vaultManager.refreshItems(session: session, at: currentFolderURL)
            } label: {
                Image(systemName: "house.fill")
            }
            .buttonStyle(.plain)
            
            ForEach(navigationStack.indices, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Button {
                    navigationStack = Array(navigationStack.prefix(index + 1))
                    try? vaultManager.refreshItems(session: session, at: currentFolderURL)
                } label: {
                    Text(navigationStack[index].lastPathComponent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    var unlockedView: some View {
        ScrollView {
            VStack {
                if session.unlockedItems.isEmpty {
                    emptyVaultView
                } else if filteredItems.isEmpty {
                    noSearchResultsView
                } else {
                    fileGridView
                }
            }
            .frame(maxWidth: .infinity, minHeight: 600, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture {
                selection.removeAll()
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.startLocation }
                        dragEnd = value.location
                        updateSelectionForMarquee()
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragEnd = nil
                    }
            )
        }
        .background(Color(NSColor.controlBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search files...")
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls: urls)
            return true
        }
        .onKeyPress(.space) {
            if let first = selection.first, let item = filteredItems.first(where: { $0.id == first }) {
                previewURL = item.url
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
                FileGridView(item: item, isSelected: selection.contains(item.id))
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    itemFrames[item.id] = geo.frame(in: .named("container"))
                                }
                                .onChange(of: geo.frame(in: .named("container"))) { _, newValue in
                                    itemFrames[item.id] = newValue
                                }
                        }
                    )
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if selection.contains(item.id) {
                                selection.remove(item.id)
                            } else {
                                selection.insert(item.id)
                            }
                        } else {
                            selection = [item.id]
                        }
                    }
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            navigationStack.append(item.url)
                            try? vaultManager.refreshItems(session: session, at: item.url)
                            selection.removeAll()
                        } else {
                            previewURL = item.url
                        }
                    }
                    .contextMenu {
                        if item.isDirectory {
                            Button("Open Folder") {
                                navigationStack.append(item.url)
                                try? vaultManager.refreshItems(session: session, at: item.url)
                            }
                        } else {
                            Button {
                                previewURL = item.url
                            } label: {
                                Label("Quick Look", systemImage: "eye")
                            }
                        }
                        
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            deleteItems()
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                    }
                    .draggable(item.url)
            }
        }
        .padding()
        .coordinateSpace(name: "container")
    }
    
    private func updateSelectionForMarquee() {
        guard let start = dragStart, let end = dragEnd else { return }
        let marqueeRect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        var newSelection = Set<UUID>()
        for (id, frame) in itemFrames {
            if marqueeRect.intersects(frame) {
                newSelection.insert(id)
            }
        }
        
        if NSEvent.modifierFlags.contains(.command) {
            selection.formUnion(newSelection)
        } else {
            selection = newSelection
        }
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
                try? await vaultManager.encryptFile(at: url, session: session, targetFolder: currentFolderURL)
            }
        }
    }
    
    private func deleteItems() {
        let itemsToDelete = filteredItems.filter { selection.contains($0.id) }
        for item in itemsToDelete {
            try? FileManager.default.removeItem(at: item.url)
        }
        try? vaultManager.refreshItems(session: session, at: currentFolderURL)
        selection.removeAll()
    }
}

struct FileGridView: View {
    let item: VaultItem
    let isSelected: Bool
    
    var body: some View {
        VStack {
            if item.isDirectory {
                Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
            }
            
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
