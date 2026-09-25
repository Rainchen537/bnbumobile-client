import Foundation

/// Called on a serial queue. A handle binds staging to the exact save-panel
/// destination; Dart can discard it if its account/modal lease expires.
final class CourseArchiveExportStore {
  private struct Pending {
    let destination: URL
    let directory: URL
    let file: URL
    let scoped: Bool
  }

  private let manager = FileManager.default
  private var pending: [String: Pending] = [:]
  private enum ExportError: Error { case invalidFile, busy, unknownHandle }

  func prepare(sourcePath: String, destinationPath: String) throws -> String {
    guard pending.isEmpty else { throw ExportError.busy }
    guard sourcePath.hasPrefix("/"), destinationPath.hasPrefix("/") else {
      throw ExportError.invalidFile
    }
    let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard source != destination,  values.isRegularFile == true,
          let bytes = values.fileSize, bytes > 0, bytes <= 512 * 1024 * 1024 else {
      throw ExportError.invalidFile
    }
    let scoped = destination.startAccessingSecurityScopedResource()
    var directory: URL?
    do {
      // Foundation creates this directory on the appropriate volume and with
      // the sandbox support needed for an atomic save of a selected file.
      let staging = try manager.url(for: .itemReplacementDirectory,
        in: .userDomainMask, appropriateFor: destination, create: true)
      directory = staging
      let file = staging.appendingPathComponent(source.lastPathComponent)
      try manager.copyItem(at: source, to: file)
      guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes else {
        throw ExportError.invalidFile
      }
      let id = UUID().uuidString
      pending[id] = Pending(destination: destination, directory: staging, file: file, scoped: scoped)
      return id
    } catch {
      if let directory { try? manager.removeItem(at: directory) }
      if scoped { destination.stopAccessingSecurityScopedResource() }
      throw error
    }
  }

  func commit(_ id: String) throws {
    guard let item = pending.removeValue(forKey: id) else { throw ExportError.unknownHandle }
    defer { clean(item) }
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: item.destination, options: .forReplacing,
      error: &coordinationError) { destination in
      do {
        if manager.fileExists(atPath: destination.path) {
          _ = try manager.replaceItemAt(destination, withItemAt: item.file)
        } else {
          try manager.moveItem(at: item.file, to: destination)
        }
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }

  func discard(_ id: String) {
    if let item = pending.removeValue(forKey: id) { clean(item) }
  }

  private func clean(_ item: Pending) {
    try? manager.removeItem(at: item.directory)
    if item.scoped { item.destination.stopAccessingSecurityScopedResource() }
  }

  deinit { for item in pending.values { clean(item) } }
}

/// Separate from Save As: a user-selected directory needs a persistent scoped
/// bookmark. Only the two desktop iSpace destinations may use this store.
/// File operations are called on the window's serial export queue.
final class DesktopDownloadStore {
  private struct Pending {
    let folder: URL
    let staging: URL
    let name: String
    let scoped: Bool
  }
  private enum DownloadError: Error { case invalidPurpose, invalidFile, unavailable, unknownHandle }
  private let manager = FileManager.default
  private let defaults: UserDefaults
  private let downloads: URL?
  private let sourceRoots: [URL]
  private var pending: [String: Pending] = [:]

  init(defaults: UserDefaults = .standard, downloads: URL? = nil, sourceRoots: [URL]? = nil) {
    self.defaults = defaults
    self.downloads = downloads
    self.sourceRoots = sourceRoots ?? [FileManager.default.temporaryDirectory]
      + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      + FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
  }

  private func key(_ purpose: String) throws -> String {
    guard ["single", "archive"].contains(purpose) else { throw DownloadError.invalidPurpose }
    return "bnbu.desktop-downloads.v1.\(purpose)"
  }

  func directory(_ purpose: String) throws -> URL {
    let key = try key(purpose)
    guard let data = defaults.data(forKey: key) else {
      guard let url = downloads ?? manager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
        throw DownloadError.unavailable
      }
      // In an App Sandbox, Data/Downloads is a symlink to the real Downloads.
      // Checking isDirectory on the unresolved link incorrectly rejects it.
      return url.resolvingSymlinksInPath()
    }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    if stale {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      defaults.set(try url.bookmarkData(options: .withSecurityScope,
        includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key)
    }
    return url
  }

  func choose(_ url: URL, purpose: String) throws {
    let key = try key(purpose)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
      throw DownloadError.unavailable
    }
    let data = try url.bookmarkData(options: .withSecurityScope,
      includingResourceValuesForKeys: nil, relativeTo: nil)
    defaults.set(data, forKey: key)
  }

  func reset(_ purpose: String) throws -> URL {
    defaults.removeObject(forKey: try key(purpose))
    return try directory(purpose)
  }

  func withSavedFile<T>(_ path: String, action: (URL) throws -> T) throws -> T {
    for purpose in ["single", "archive"] {
      guard let folder = try? directory(purpose) else { continue }
      let scoped = folder.startAccessingSecurityScopedResource()
      defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
      let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let parent = folder.standardizedFileURL.resolvingSymlinksInPath()
      guard file.deletingLastPathComponent().path == parent.path else { continue }
      guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        throw DownloadError.invalidFile
      }
      return try action(file)
    }
    throw DownloadError.invalidFile
  }

  func prepare(sourcePath: String, fileName: String, purpose: String) throws -> String {
    let folder = try directory(purpose)
    let scoped = folder.startAccessingSecurityScopedResource()
    var staging: URL?
    do {
      let source = URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath()
      guard sourcePath.hasPrefix("/"), !fileName.isEmpty, fileName != ".", fileName != "..",
        !fileName.contains("/"), !fileName.contains("\\"),
        !fileName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
        sourceRoots.contains(where: { source.path.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/") }),
        try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
        throw DownloadError.invalidFile
      }
      let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true, let bytes = values.fileSize,
        bytes <= 1024 * 1024 * 1024 else { throw DownloadError.invalidFile }
      let temp = folder.appendingPathComponent(".bnbu-download-\(UUID().uuidString)", isDirectory: true)
      try manager.createDirectory(at: temp, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      staging = temp
      let file = temp.appendingPathComponent("download")
      try manager.copyItem(at: source, to: file)
      guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes else {
        throw DownloadError.invalidFile
      }
      let id = UUID().uuidString
      pending[id] = Pending(folder: folder, staging: temp, name: fileName, scoped: scoped)
      return id
    } catch {
      if let staging { try? manager.removeItem(at: staging) }
      if scoped { folder.stopAccessingSecurityScopedResource() }
      throw error
    }
  }

  func commit(_ id: String) throws -> String {
    guard let item = pending.removeValue(forKey: id) else { throw DownloadError.unknownHandle }
    defer { clean(item) }
    let name = item.name as NSString
    let ext = name.pathExtension.isEmpty ? "" : "." + name.pathExtension
    for suffix in 1...999 {
      let leaf = suffix == 1 ? item.name : "\(name.deletingPathExtension) (\(suffix))\(ext)"
      let destination = item.folder.appendingPathComponent(leaf)
      if manager.fileExists(atPath: destination.path) { continue }
      do {
        // moveItem fails if another process won the name; never replace it.
        try manager.moveItem(at: item.staging.appendingPathComponent("download"), to: destination)
        return destination.path
      } catch {
        if manager.fileExists(atPath: destination.path) { continue }
        throw error
      }
    }
    throw DownloadError.unavailable
  }

  func discard(_ id: String) {
    if let item = pending.removeValue(forKey: id) { clean(item) }
  }

  private func clean(_ item: Pending) {
    try? manager.removeItem(at: item.staging)
    if item.scoped { item.folder.stopAccessingSecurityScopedResource() }
  }

  deinit { for item in pending.values { clean(item) } }
}
