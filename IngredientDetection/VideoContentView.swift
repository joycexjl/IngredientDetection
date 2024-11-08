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
                // 显示视频检测界面
                VideoViewControllerRepresentable(videoURL: videoURL)
                    .edgesIgnoringSafeArea(.all)
            } else {
                // 显示视频选择界面
                VStack(spacing: 20) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            
                            Text("选择视频")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            // 保存视频到临时目录
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