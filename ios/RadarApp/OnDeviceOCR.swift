import Foundation
import UIKit
import Vision
import PhotosUI
import RadarCore

struct ScreenOCRResult {
    let text:String
    let confidence:Float
}
enum OnDeviceOCR {
    static func read(image:UIImage) async throws -> ScreenOCRResult {
        guard let image=image.cgImage else {throw NSError(domain:"RadarOCR",code:1,userInfo:[NSLocalizedDescriptionKey:"Cannot read screenshot"])}
        return try await Task.detached(priority:.userInitiated){
            let req=VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false // Money, mileage, merchant IDs must not be silently rewritten.
            req.recognitionLanguages=["en-US"]
            let handler=VNImageRequestHandler(cgImage:image,options:[:])
            try handler.perform([req])
            let lines=(req.results ?? []).compactMap{$0.topCandidates(1).first}
            let confidence=lines.isEmpty ? 0 : lines.reduce(0){$0+$1.confidence}/Float(lines.count)
            return ScreenOCRResult(text:lines.map(\.string).joined(separator:"\n"),confidence:confidence)
        }.value
    }
}
/// Offer parsing happens in the existing API, which also handles duplicates and lifecycle gates.
/// Native Vision runs locally; only recognized text and optional GPS reach Radar's server.
