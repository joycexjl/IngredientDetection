//
//  IngredientDetectionApp.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/4/24.
//

import SwiftUI


@main
struct IngredientDetectionApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

struct MainView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Ingredient Detection")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                NavigationLink(destination: CameraView()) {
                    DetectionOptionButton(
                        title: "Camera Detection",
                        subtitle: "Detect ingredients from camera",
                        systemImage: "camera.fill"
                    )
                }
                
                NavigationLink(destination: VideoContentView()) {
                    DetectionOptionButton(
                        title: "Video Detection",
                        subtitle: "Detect ingredients from video",
                        systemImage: "video.fill"
                    )
                }
            }
            .padding()
        }
    }
}

struct DetectionOptionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.blue)
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

#Preview {
    MainView()
}