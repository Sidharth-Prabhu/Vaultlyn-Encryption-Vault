import Foundation
import SwiftUI

@Observable
class ImportManager {
    static let shared = ImportManager()
    
    var pendingURLs: [URL] = []
    var isShowingImportSheet: Bool = false
    
    private init() {}
    
    @MainActor
    func handleExternalFiles(_ urls: [URL]) {
        self.pendingURLs = urls
        self.isShowingImportSheet = !urls.isEmpty
    }
    
    func clear() {
        pendingURLs = []
        isShowingImportSheet = false
    }
}
