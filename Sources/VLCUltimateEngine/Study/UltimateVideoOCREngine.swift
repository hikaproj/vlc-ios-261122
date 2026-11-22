//
//  UltimateVideoOCREngine.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  On-Device Vision Text Recognition (OCR) for Paused Video Frames & In-Video Subtitle Copy.
//

import Foundation
import Vision
import CoreVideo
import UIKit

public struct OCRTextItem: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let boundingBox: CGRect // Normalized (0.0 - 1.0) in UIKit coordinates (top-left origin)
    public let confidence: Float
    
    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

public final class UltimateVideoOCREngine: @unchecked Sendable {
    
    public static let shared = UltimateVideoOCREngine()
    
    private let queue = DispatchQueue(label: "org.videolan.vlc.ultimate.ocr", qos: .userInitiated)
    
    private init() {}
    
    /// Executes on-device OCR on the provided CVPixelBuffer using VNRecognizeTextRequest (.accurate).
    public func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        completion: @escaping @Sendable ([OCRTextItem]) -> Void
    ) {
        queue.async {
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                var items: [OCRTextItem] = []
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    
                    // Convert Vision coordinates (bottom-left origin) to UIKit (top-left origin)
                    let box = obs.boundingBox
                    let uiKitBox = CGRect(
                        x: box.origin.x,
                        y: 1.0 - box.origin.y - box.size.height,
                        width: box.size.width,
                        height: box.size.height
                    )
                    
                    items.append(OCRTextItem(
                        text: candidate.string,
                        boundingBox: uiKitBox,
                        confidence: candidate.confidence
                    ))
                }
                
                DispatchQueue.main.async {
                    completion(items)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "ja-JP", "zh-Hans", "es-ES", "fr-FR", "de-DE"]
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }
}
