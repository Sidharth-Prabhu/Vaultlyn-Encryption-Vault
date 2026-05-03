//
//  VaultDetailView.swift
//  Vaultlyn
//
//  Created by Sidharth Prabhu on 2026-05-02.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLook

enum ViewMode: String, CaseIterable {
    case grid = "square.grid.2x2"
    case list = "list.bullet"
}

struct VaultDetailView: View {
    let vault: Vault
    @State private var vaultManager = VaultManager.shared
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var selection: Set<UUID> = []
    @State private var previewURL: URL?
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    
    // Navigation state
    @State private var navigationStack: [URL] = []
    
    // Recovery state
    @State private var recoveredWithKey = false
    @State private var showingResetPassword = false
    @State private var newPassword = ""
    
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
                if session.isProcessing {
                    processingView
                } else if session.isUnlocked {
                    if recoveredWithKey {
                        recoveryAlertBar
                    }
                    breadcrumbBar
                    Divider()
                    unlockedView
                } else {
                    lockedView
                }
            }
            
            // Marquee Rect (only in grid)
            if viewMode == .grid, let start = dragStart, let end = dragEnd {
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
            if session.isUnlocked && !session.isProcessing {
                ToolbarItemGroup {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Button(action: { 
                        Task { @MainActor in
                            await vaultManager.lock(vault: vault)
                            recoveredWithKey = false
                        }
                    }) {
                        Label("Lock", systemImage: "lock.fill")
                    }
                }
                
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
            }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingResetPassword) {
            resetPasswordSheet
        }
        .onChange(of: vault) { _, _ in
            navigationStack = []
            recoveredWithKey = false
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
        Group {
            if session.unlockedItems.isEmpty {
                emptyVaultView
            } else if filteredItems.isEmpty {
                noSearchResultsView
            } else {
                if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
            }
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
    
    private var gridView: some View {
        ScrollView {
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
                            handleSelection(item: item)
                        }
                        .onTapGesture(count: 2) {
                            handleOpen(item: item)
                        }
                        .contextMenu { itemContextMenu(item: item) }
                        .draggable(item.url)
                }
            }
            .padding()
            .coordinateSpace(name: "container")
            .frame(maxWidth: .infinity, minHeight: 600, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { selection.removeAll() }
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
    }
    
    private var listView: some View {
        Table(filteredItems, selection: $selection) {
            TableColumn("Name") { item in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(item.name)
                        .foregroundStyle(item.isDirectory ? Color.accentColor : .primary)
                }
                .onTapGesture(count: 2) {
                    handleOpen(item: item)
                }
            }
            
            TableColumn("Date Modified") { item in
                Text(item.modificationDate.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            
            TableColumn("Size") { item in
                Text(item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            
            TableColumn("Kind") { item in
                Text(item.isDirectory ? "Folder" : (try? item.url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription) ?? "File")
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if let firstId = selection.first, let item = filteredItems.first(where: { $0.id == firstId }) {
                itemContextMenu(item: item)
            }
        }
    }
    
    private func handleSelection(item: VaultItem) {
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
    
    private func handleOpen(item: VaultItem) {
        if item.isDirectory {
            navigationStack.append(item.url)
            try? vaultManager.refreshItems(session: session, at: item.url)
            selection.removeAll()
        } else {
            previewURL = item.url
        }
    }
    
    @ViewBuilder
    private func itemContextMenu(item: VaultItem) -> some View {
        if item.isDirectory {
            Button("Open Folder") {
                handleOpen(item: item)
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
    
    var recoveryAlertBar: some View {
        HStack {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text("Vault unlocked with recovery key.")
                .font(.subheadline)
            Spacer()
            Button("Change Password") {
                showingResetPassword = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
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
        VStack(spacing: 24) {
            if vault.isLockedOut {
                lockoutView
            } else {
                standardLockedView
            }
        }
        .padding()
    }
    
    var standardLockedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Unlock \(vault.name)")
                .font(.title2)
            
            VStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onSubmit { unlock() }
                
                if vault.failedAttempts > 0 {
                    Text("\(5 - vault.failedAttempts) attempts remaining")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            if let error = errorMessage {
                errorBanner(message: error)
            }
            
            HStack(spacing: 12) {
                Button("Unlock Vault") {
                    unlock()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || session.isProcessing)
                
                Button("Use Recovery Key") {
                    recoverVault()
                }
                .buttonStyle(.bordered)
            }
            
            recoveryStatusIndicator
        }
    }
    
    var lockoutView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            
            VStack(spacing: 8) {
                Text("Security Lockout")
                    .font(.title2)
                Text("Too many failed password attempts. Access is disabled for your protection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Text("To regain access, please select your recovery key (.vaultkey) generated during vault creation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                
                Button("Select Recovery Key...") {
                    recoverVault()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            
            if let error = errorMessage {
                errorBanner(message: error)
            }
            
            recoveryStatusIndicator
        }
        .padding()
        .frame(maxWidth: 400)
    }
    
    var resetPasswordSheet: some View {
        VStack(spacing: 20) {
            Text("Reset Vault Password")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("You've unlocked this vault with a recovery key. It is highly recommended to set a new master password now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Later") {
                    showingResetPassword = false
                }
                
                Button("Reset & Re-encrypt") {
                    performReset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
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
        errorMessage = nil
        let currentPassword = password
        Task { @MainActor in
            do {
                try await vaultManager.unlock(vault: vault, password: currentPassword)
                password = ""
                vault.failedAttempts = 0
                vault.isLockedOut = false
            } catch {
                vault.failedAttempts += 1
                if vault.failedAttempts >= 5 {
                    vault.isLockedOut = true
                    errorMessage = "Vault locked due to too many attempts."
                } else {
                    errorMessage = "Invalid password. \(5 - vault.failedAttempts) attempts remaining."
                }
            }
        }
    }
    
    private func recoverVault() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "vaultkey") ?? .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Select the recovery key for '\(vault.name)'"
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                print("DEBUG: Recovery key selected: \(url.path)")
                do {
                    let keyData = try Data(contentsOf: url)
                    guard let encryptedMaster = vault.encryptedMasterPassword else {
                        print("DEBUG: Missing encryptedMasterPassword")
                        errorMessage = "This vault was created without recovery data. Recovery is not possible."
                        return
                    }
                    
                    // Decrypt the master password using the recovery key
                    let masterPasswordData = try SecurityManager.shared.decryptWithRecoveryKey(encryptedMaster, recoveryKey: keyData)
                    let recoveredPassword = String(data: masterPasswordData, encoding: .utf8) ?? ""
                    
                    if recoveredPassword.isEmpty {
                        print("DEBUG: Recovered password is empty")
                        errorMessage = "Corrupted recovery data."
                        return
                    }
                    
                    Task { @MainActor in
                        do {
                            print("DEBUG: Starting direct unlock with recovered password...")
                            // Directly unlock using the recovered password
                            try await vaultManager.unlock(vault: vault, password: recoveredPassword)
                            
                            // Reset lockout state
                            vault.failedAttempts = 0
                            vault.isLockedOut = false
                            recoveredWithKey = true
                            
                            // Ask to reset password
                            showingResetPassword = true
                            errorMessage = nil 
                            print("DEBUG: Recovery unlock successful!")
                        } catch {
                            print("DEBUG: Unlock failed: \(error.localizedDescription)")
                            errorMessage = "Recovery unlock failed: \(error.localizedDescription)"
                        }
                    }
                } catch {
                    print("DEBUG: Decryption or File Read failed: \(error.localizedDescription)")
                    errorMessage = "Invalid recovery key or decryption failed. Please ensure you selected the correct .vaultkey file."
                }
            }
        }
    }
    
    private func performReset() {
        let currentRecoveredPassword = session.sessionKey ?? ""
        let targetNewPassword = newPassword
        
        Task { @MainActor in
            do {
                try await vaultManager.changePassword(vault: vault, oldPassword: currentRecoveredPassword, newPassword: targetNewPassword)
                recoveredWithKey = false
                showingResetPassword = false
                newPassword = ""
            } catch {
                errorMessage = "Failed to reset password."
            }
        }
    }
    
    private func handleDrop(urls: [URL]) {
        // Filter out URLs that are already inside this vault to prevent duplicates/re-imports
        let vaultRoot = URL(fileURLWithPath: vault.rootPath).standardized
        let externalURLs = urls.filter { url in
            !url.standardized.path.hasPrefix(vaultRoot.path)
        }
        
        guard !externalURLs.isEmpty else { return }
        
        Task { @MainActor in
            do {
                try await vaultManager.importFiles(urls: externalURLs, session: session, targetFolder: currentFolderURL)
            } catch {
                errorMessage = "Failed to import some files: \(error.localizedDescription)"
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
    
    @ViewBuilder
    func errorBanner(message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: 280)
            .background(Color.red.opacity(0.8))
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    var recoveryStatusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: vault.encryptedMasterPassword != nil ? "checkmark.shield.fill" : "xmark.shield.fill")
            Text(vault.encryptedMasterPassword != nil ? "Recovery Enabled" : "No Recovery Data")
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(vault.encryptedMasterPassword != nil ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
        .padding(.top, 10)
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
