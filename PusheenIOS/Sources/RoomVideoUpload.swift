import Foundation
import UniformTypeIdentifiers

/// Builds a disk-backed request with bounded memory, including for long MOVs.
enum RoomVideoUpload {
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func validate(_ file: URL, maximumBytes: Int64) throws {
        guard supportedExtensions.contains(file.pathExtension.lowercased()) else {
            throw Failure("Выберите видео MP4, MOV или M4V.")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw Failure("Файл видео пустой или недоступен.") }
        guard size <= maximumBytes else {
            let limit = ByteCountFormatter.string(fromByteCount: maximumBytes, countStyle: .file)
            throw Failure("Видео слишком большое. Лимит сервера: \(limit).")
        }
    }

    static func makeBody(file: URL, boundary: String, title: String, duration: Double) throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pusheen-upload-\(UUID().uuidString).body")
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: destination) } }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw Failure("Не удалось подготовить видео. Проверьте свободное место на iPhone.")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let name = file.lastPathComponent
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "video/mp4"
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\(title)\r\n".utf8))
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"duration_seconds\"\r\n\r\n\(duration)\r\n".utf8))
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        while true {
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try output.close()
        completed = true
        return destination
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

final class RoomVideoUploadProgress: NSObject, URLSessionTaskDelegate {
    private let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }
}
