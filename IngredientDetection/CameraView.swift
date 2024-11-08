//
//  ContentView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/4/24.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    var body: some View {
        VisionObjectRecognitionViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}

// SwiftUI wrapper for VisionObjectRecognitionViewController
struct VisionObjectRecognitionViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> VisionObjectRecognitionViewController {
        return VisionObjectRecognitionViewController()
    }
    
    func updateUIViewController(_ uiViewController: VisionObjectRecognitionViewController, context: Context) {
        // Updates can be handled here if needed
    }
}
