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
    init() {
        // Customize the navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.setBackIndicatorImage(
            UIImage(systemName: "chevron.left")?.withTintColor(.white, renderingMode: .alwaysOriginal),
            transitionMaskImage: UIImage(systemName: "chevron.left")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        )
        appearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        
        // Add padding to move the back button away from the edge
        appearance.buttonAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 10, vertical: 0)
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
        
        // Add leading padding to the navigation bar items
        UINavigationBar.appearance().layoutMargins.left = 20
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Ingredient Detection")
                    .font(.custom("Jost", size: 34))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                NavigationLink(destination: CameraView()) {
                    DetectionOptionButton(
                        title: "Real-Time Detection",
                        subtitle: "Detect ingredients from live session",
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color(red: 54/255, green: 94/255, blue: 50/255)
                    .opacity(0.93)
                    .ignoresSafeArea()
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
                    .font(.custom("Jost", size: 16))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.custom("Jost", size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

//#Preview {
//    MainView()
//}
