//
//  Detection.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/5/24.
//

import SwiftUI
import Vision

struct Detection: Identifiable {
    let id: UUID
    let boundingBox: CGRect
    let label: String
    let confidence: VNConfidence
}

class DetectionStore: ObservableObject {
    @Published var detections: [Detection] = []
    @Published var trackedObjects: [UUID: VNDetectedObjectObservation] = [:]
    
    // Minimum confidence threshold for tracking
    let confidenceThreshold: Float = 0.4
}
