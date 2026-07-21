// ocr-image.swift — local macOS Vision OCR for the AIOS capture Pass-0.
// Usage:  swift hooks/ocr-image.swift <image-path> [--no-correction]
//           → prints recognized text (stdout).
//         --no-correction disables language correction (use for code, serials,
//           IDs — Vision's autocorrect mangles tokens like C001 → "cool").
//           Used by video-watch.py's OCR reader in --code mode.
// Fully local (Apple Vision framework); no network, Fortress-clean.
import Foundation
import Vision
import AppKit

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: ocr-image.swift <image> [--no-correction]\n".data(using: .utf8)!)
    exit(2)
}
let noCorrection = args.contains("--no-correction")
let path = args.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? args[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("ocr: cannot load image at \(path)\n".data(using: .utf8)!)
    exit(3)
}
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = !noCorrection
if #available(macOS 13.0, *) { req.automaticallyDetectsLanguage = true }
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do {
    try handler.perform([req])
    let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    print(lines.joined(separator: "\n"))
} catch {
    FileHandle.standardError.write("ocr: \(error)\n".data(using: .utf8)!)
    exit(4)
}
