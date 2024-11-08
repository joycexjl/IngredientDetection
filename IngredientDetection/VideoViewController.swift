//
//  ControllerView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/8/24.
//

import UIKit
import AVFoundation
import Vision
import CoreML
import Accelerate

class VideoViewController: VisionObjectRecognitionViewController {
    // MARK: - Properties
    private var videoPlayer: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?

    let videoURL: URL
    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle
    override func setupAVCapture() {
        setupLocalVideo()
        setupVision()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDetectionTimer()
        videoPlayer?.pause()
    }
    
    // MARK: - Video Setup
    private func setupLocalVideo() {
        print("Setting up local video")
        let playerItem = AVPlayerItem(url: videoURL)
        
        let settings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        playerItem.add(videoOutput!)
        
        videoPlayer = AVPlayer(playerItem: playerItem)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let playerLayer = AVPlayerLayer(player: self.videoPlayer)
            playerLayer.frame = self.view.bounds
            playerLayer.videoGravity = .resizeAspectFill
            self.rootLayer = self.view.layer
            self.rootLayer.addSublayer(playerLayer)
            
            self.videoPlayer?.play()
            self.startDetectionTimer()
        }
    }
    
    // MARK: - Frame Processing
    override func processCurrentFrame() {
        guard !isProcessingFrame,
              let output = videoOutput else { return }
        
        videoPlayer?.pause()
        
        let itemTime = videoPlayer?.currentItem?.currentTime() ?? .zero
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            videoPlayer?.play()
            return
        }
        
        isProcessingFrame = true
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print("Failed to process video frame: \(error)")
        }
        
        isProcessingFrame = false
        videoPlayer?.play()
    }
    
    // MARK: - Layer Setup
    override func setupLayers() {
        guard rootLayer != nil else {
            rootLayer = view.layer
            return
        }
        
        detectionOverlay?.removeFromSuperlayer()
        
        guard let playerLayer = view.layer.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer else {
            print("Error: AVPlayerLayer not found")
            return
        }
        
        let videoRect = playerLayer.videoRect
        detectionOverlay = CALayer()
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = videoRect
        detectionOverlay.position = CGPoint(x: videoRect.midX, y: videoRect.midY)
        // detectionOverlay.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        detectionOverlay.zPosition = 999
        
        rootLayer.addSublayer(detectionOverlay)
    }
    
    // MARK: - Timer Management
    private func startDetectionTimer() {
        stopDetectionTimer()
        detectionTimer = Timer.scheduledTimer(
            withTimeInterval: 0.2,
            repeats: true
        ) { [weak self] _ in
            self?.processCurrentFrame()
        }
    }
    
    private func stopDetectionTimer() {
        detectionTimer?.invalidate()
        detectionTimer = nil
    }
}