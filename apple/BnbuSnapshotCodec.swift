import Foundation

/// Decodes both Dart ISO-8601 timestamps (milliseconds/microseconds) and legacy
/// whole-second snapshots. No snapshot values are included in decoding errors.
enum BnbuSnapshotCodec {
  static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let wholeSeconds = ISO8601DateFormatter()
    wholeSeconds.formatOptions = [.withInternetDateTime]
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      guard let date = fractional.date(from: value) ?? wholeSeconds.date(from: value) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Invalid snapshot timestamp"
        )
      }
      return date
    }
    return decoder
  }
}
