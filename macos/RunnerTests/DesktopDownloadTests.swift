import Foundation

@main
struct DesktopDownloadTests {
  static func main() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let downloads = root.appendingPathComponent("Downloads").resolvingSymlinksInPath()
    let custom = root.appendingPathComponent("Custom")
    try manager.createDirectory(at: downloads, withIntermediateDirectories: true)
    try manager.createDirectory(at: custom, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let suite = "bnbu.desktop-download-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DesktopDownloadStore(defaults: defaults, downloads: downloads, sourceRoots: [root])
    precondition(tryValue { try store.directory("single").resolvingSymlinksInPath().path } == downloads.resolvingSymlinksInPath().path)
    precondition(tryValue { try store.directory("archive").resolvingSymlinksInPath().path } == downloads.resolvingSymlinksInPath().path)
    try store.choose(custom, purpose: "single")
    precondition(tryValue { try store.directory("single").resolvingSymlinksInPath().path } == custom.resolvingSymlinksInPath().path)
    precondition(tryValue { try store.directory("archive").resolvingSymlinksInPath().path } == downloads.resolvingSymlinksInPath().path)
    let restored = DesktopDownloadStore(defaults: defaults, downloads: downloads, sourceRoots: [root])
    precondition(tryValue { try restored.directory("single").resolvingSymlinksInPath().path } == custom.resolvingSymlinksInPath().path)
    _ = try store.reset("single")
    precondition(tryValue { try restored.directory("single").resolvingSymlinksInPath().path } == downloads.resolvingSymlinksInPath().path)
    let source = root.appendingPathComponent("fixture.pdf")
    let bytes = Data("synthetic PDF".utf8)
    try bytes.write(to: source)
    let sandboxAlias = root.appendingPathComponent("SandboxDownloads")
    try manager.createSymbolicLink(at: sandboxAlias, withDestinationURL: downloads)
    let aliasStore = DesktopDownloadStore(defaults: defaults, downloads: sandboxAlias, sourceRoots: [root])
    let aliasId = try aliasStore.prepare(sourcePath: source.path, fileName: "symlink.pdf", purpose: "single")
    let aliasSaved = try aliasStore.commit(aliasId)
    precondition(tryValue { try Data(contentsOf: URL(fileURLWithPath: aliasSaved)) } == bytes)
    try manager.removeItem(atPath: aliasSaved)
    let old = downloads.appendingPathComponent("fixture.pdf")
    try Data("old file".utf8).write(to: old)
    let id = try store.prepare(sourcePath: source.path, fileName: "fixture.pdf", purpose: "single")
    let target = try store.commit(id)
    precondition(target != old.path)
    precondition(tryValue { try Data(contentsOf: URL(fileURLWithPath: target)) } == bytes)
    precondition(tryValue { try String(contentsOf: old, encoding: .utf8) } == "old file")
    let cancelled = try store.prepare(sourcePath: source.path, fileName: "cancelled.pdf", purpose: "archive")
    store.discard(cancelled)
    precondition(!manager.fileExists(atPath: downloads.appendingPathComponent("cancelled.pdf").path))
    do { _ = try store.commit(cancelled); preconditionFailure("Replayed handle") } catch {}
    do { _ = try store.prepare(sourcePath: source.path, fileName: "../escape.pdf", purpose: "single"); preconditionFailure("Traversal") } catch {}
    do { _ = try store.prepare(sourcePath: "/etc/hosts", fileName: "hosts", purpose: "single"); preconditionFailure("Source outside cache") } catch {}
    do { _ = try store.directory("arbitrary"); preconditionFailure("Unknown purpose") } catch {}
    let entries = try manager.contentsOfDirectory(atPath: downloads.path)
    precondition(entries.count == 2 && !entries.contains { $0.hasPrefix(".bnbu") })
    let opened = try store.withSavedFile(target) { $0.path }
    precondition(opened == URL(fileURLWithPath: target).resolvingSymlinksInPath().path)
    do { _ = try store.withSavedFile(source.path) { $0 }; preconditionFailure("Opening outside destination") } catch {}
    print("Desktop downloads: independent bookmarks, reset, atomic save, collision, cancellation, replay and path boundaries passed")
  }
  static func tryValue<T>(_ action: () throws -> T) -> T { try! action() }
}
