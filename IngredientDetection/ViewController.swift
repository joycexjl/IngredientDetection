//
//  ViewController.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/5/24.
//

import UIKit
import AVFoundation
import Vision
import CoreML
import Accelerate

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    
    private var previewView: UIView!
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("ViewController - viewDidLoad started")
        
        // Create the preview view programmatically
        previewView = UIView(frame: view.bounds)
        previewView.contentMode = .scaleAspectFill
        view.addSubview(previewView)
        print("ViewController - Preview view created and added")
        
        // Add constraints to make preview view fill the entire view
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        print("ViewController - Setting up AV capture")
        setupAVCapture()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupAVCapture() {
        print("ViewController - setupAVCapture started")
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device, make an input
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        print("ViewController - Video device found: \(String(describing: videoDevice?.localizedName))")
        
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
            print("ViewController - Device input created successfully")
        } catch {
            print("Could not create video device input: \(error)")
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // Model image size is smaller.
        
        // Add a video input
        guard session.canAddInput(deviceInput) else {
            print("ViewController - Could not add video device input to the session")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            // Add a video data output
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            print("ViewController - Could not add video data output to the session")
            session.commitConfiguration()
            return
        }
        let captureConnection = videoDataOutput.connection(with: .video)
        // Always process the frames
        captureConnection?.isEnabled = true
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        session.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        rootLayer = previewView.layer
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
        print("ViewController - Preview layer setup complete")
    }
    
    func startCaptureSession() {
        print("ViewController - Starting capture session on background thread")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            print("ViewController - Capture session started")
        }
    }
    
    // Clean up capture setup
    func teardownAVCapture() {
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
        // print("frame dropped")
    }
    
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            startCaptureSession()
        }
    }
}

class VideoViewController: VisionObjectRecognitionViewController {
    // MARK: - Properties
    private var videoPlayer: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoURL: URL = URL(fileURLWithPath: "/Users/shangyunle/Downloads/video.mp4")
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocalVideo()
        setupVision()
        setupLayers()
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
        detectionOverlay.frame = videoRect
        detectionOverlay.position = CGPoint(x: videoRect.midX, y: videoRect.midY)
        detectionOverlay.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        detectionOverlay.zPosition = 999
        
        view.layer.addSublayer(detectionOverlay)
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