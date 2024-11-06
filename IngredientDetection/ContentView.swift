//
//  ContentView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/4/24.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var detectionStore = DetectionStore()
    
    var body: some View {
        ZStack {
            ControllerView()
                .edgesIgnoringSafeArea(.all)
            
            // DetectionBoxesView(detections: detectionStore.detections)
        }
    }
}

struct DetectionBoxesView: View {
    let detections: [Detection]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = CGRect(
                    x: detection.boundingBox.minX * geometry.size.width,
                    y: (1 - detection.boundingBox.maxY) * geometry.size.height,
                    width: detection.boundingBox.width * geometry.size.width,
                    height: detection.boundingBox.height * geometry.size.height
                )
                
                BoundingBoxView(detection: detection, rect: rect)
            }
        }
    }
}

struct BoundingBoxView: View {
    let detection: Detection
    let rect: CGRect
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .path(in: rect)
                .stroke(Color.red, lineWidth: 2)
            
            Text("\(detection.label) \(Int(detection.confidence * 100))%")
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.7))
                .font(.caption)
                .position(x: rect.minX + 5, y: rect.minY - 10)
        }
    }
}
