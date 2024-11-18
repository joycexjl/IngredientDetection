//
//  ContentView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/4/24.
//

import SwiftUI
import AVFoundation
import PhotosUI

struct VideoContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoURL: URL?
    
    var body: some View {
        Group {
            if let videoURL = videoURL {
                // Video detection view
                VideoViewControllerRepresentable(videoURL: videoURL)
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Video selection view
                VStack(spacing: 30) {
                    Text("Video Detection")
                        .font(.custom("Jost", size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 16) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                            
                            Text("Select Video")
                                .font(.custom("Jost", size: 16))
                                .foregroundColor(.white)
                            
                            Text("Choose a video to detect ingredients")
                                .font(.custom("Jost", size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color(red: 54/255, green: 94/255, blue: 50/255)
                        .opacity(0.93)
                        .ignoresSafeArea()
                )
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("mov")
                            
                            try? data.write(to: tempURL)
                            videoURL = tempURL
                        }
                    }
                }
            }
        }
    }
}

// SwiftUI wrapper for VideoViewController
struct VideoViewControllerRepresentable: UIViewControllerRepresentable {
    let videoURL: URL
    
    func makeUIViewController(context: Context) -> VideoViewController {
        let controller = VideoViewController(videoURL: videoURL)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoViewController, context: Context) {
    }
}