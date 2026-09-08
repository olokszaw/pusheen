import Foundation

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let movie = directory.appendingPathComponent("camera.MOV")
// Crosses the streaming chunk boundary and includes arbitrary binary bytes.
let bytes = Data((0..<(2 * 1024 * 1024 + 37)).map { UInt8($0 % 251) })
try bytes.write(to: movie)
try RoomVideoUpload.validate(movie, maximumBytes: Int64(bytes.count))
do {
    try RoomVideoUpload.validate(movie, maximumBytes: Int64(bytes.count - 1))
    fatalError("Oversized file was accepted")
} catch is RoomVideoUpload.Failure { }
let boundary = "GalleryRegression"
let body = try RoomVideoUpload.makeBody(file: movie, boundary: boundary, title: "Видео", duration: 7.5)
defer { try? FileManager.default.removeItem(at: body) }
let encoded = try Data(contentsOf: body)
let marker = Data("Content-Type: video/quicktime\r\n\r\n".utf8)
guard let range = encoded.range(of: marker) else { fatalError("Missing MOV MIME header") }
let ending = Data("\r\n--\(boundary)--\r\n".utf8)
precondition(encoded[range.upperBound..<(encoded.count - ending.count)] == bytes,
             "Multipart corrupted or truncated binary video bytes")
precondition(encoded.suffix(ending.count) == ending)

func temporaryBodies() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        .filter { $0.hasPrefix("pusheen-upload-") && $0.hasSuffix(".body") })
}
let beforeFailure = try temporaryBodies()
do {
    _ = try RoomVideoUpload.makeBody(file: directory.appendingPathComponent("missing.mov"),
                                    boundary: boundary, title: "missing", duration: 0)
    fatalError("Missing source was accepted")
} catch { }
let afterFailure = try temporaryBodies()
precondition(afterFailure == beforeFailure, "Failed multipart leaked a temporary body")
print("Gallery multipart and size validation tests passed")
