//
//  ContentView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/4/24.
//

import SwiftUI
import AVFoundation

struct VideoContentView: View {
    var body: some View {
        VideoViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}

// SwiftUI wrapper for VideoViewController
struct VideoViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> VideoViewController {
        return VideoViewController()
    }
    
    func updateUIViewController(_ uiViewController: VideoViewController, context: Context) {
        // Updates can be handled here if needed
    }
}