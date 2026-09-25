import Foundation

// Standalone filesystem regression; real NSSavePanel/sandbox acceptance is
// performed separately on the signed installed app.
@main
struct CourseArchiveExportTests {
  static func expectContents(_ url: URL, _ expected: Data) throws {
    let actual = try Data(contentsOf: url)
    precondition(actual == expected)
  }

  static func main() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let source = root.appendingPathComponent("source.zip")
    let destination = root.appendingPathComponent("export.zip")
    let bytes = Data(repeating: 42, count: 1024 * 1024)
    try bytes.write(to: source)
    let store = CourseArchiveExportStore()
    let first = try store.prepare(sourcePath: source.path, destinationPath: destination.path)
    precondition(!manager.fileExists(atPath: destination.path))
    try store.commit(first)
    try expectContents(destination, bytes)
    let old = Data("existing export".utf8)
    try old.write(to: destination)
    let cancelled = try store.prepare(sourcePath: source.path, destinationPath: destination.path)
    store.discard(cancelled)
    try expectContents(destination, old)
    let replacement = try store.prepare(sourcePath: source.path, destinationPath: destination.path)
    try store.commit(replacement)
    try expectContents(destination, bytes)
    do {
      _ = try store.prepare(sourcePath: root.appendingPathComponent("missing.zip").path,
        destinationPath: destination.path)
      preconditionFailure("Missing input must fail")
    } catch {}
    try expectContents(destination, bytes)
    do { try store.commit(first); preconditionFailure("A handle must not replay") } catch {}
    store.discard(first)
    let pdfSource = root.appendingPathComponent("source.pdf")
    let pdfDestination = root.appendingPathComponent("export.pdf")
    try bytes.write(to: pdfSource)
    let pdf = try store.prepare(sourcePath: pdfSource.path, destinationPath: pdfDestination.path)
    try store.commit(pdf)
    try expectContents(pdfDestination, bytes)
    print("Native export: create, replace, cancel, failed prepare, and handle replay passed")
  }
}
