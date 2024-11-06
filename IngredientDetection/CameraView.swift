//
//  CameraView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/5/24.
//

import SwiftUI
import AVFoundation
import Vision
import CoreML

struct CameraView: UIViewRepresentable {
    @ObservedObject var detectionStore: DetectionStore

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        // Set up capture session
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .vga640x480

        // Set up device input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let deviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(deviceInput) else {
            print("Could not create video device input.")
            return view
        }
        captureSession.addInput(deviceInput)

        // Set up video output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "VideoDataOutputQueue"))
        guard captureSession.canAddOutput(videoDataOutput) else {
            print("Could not add video data output.")
            return view
        }
        captureSession.addOutput(videoDataOutput)

        // Set up preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }

        // Start capture session
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Handle view updates if needed
    }

    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: CameraView
        var visionModel: VNCoreMLModel
        var detectionStore: DetectionStore
        var sequenceHandler = VNSequenceRequestHandler()
        var trackingRequests: [VNTrackObjectRequest] = []
        var lastProcessedTime = Date()

        init(_ parent: CameraView) {
            self.parent = parent
            self.detectionStore = parent.detectionStore

            // Load the ML model
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all // Adjust if needed
                let model = try yolo11x(configuration: config)
                self.visionModel = try VNCoreMLModel(for: model.model)
            } catch {
                fatalError("Failed to load Core ML model: \(error)")
            }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            let currentTime = Date()
                if currentTime.timeIntervalSince(lastProcessedTime) < 0.2 { // Process at most 5 frames per second
                    return
                }
                lastProcessedTime = currentTime
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            // If we're not tracking any objects, perform detection
            if trackingRequests.isEmpty {
                performDetection(pixelBuffer)
            } else {
                performTracking(pixelBuffer)
            }
        }

        private func performDetection(_ pixelBuffer: CVPixelBuffer) {
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self = self,
                      let results = request.results as? [VNRecognizedObjectObservation] else { return }
                
                DispatchQueue.main.async {
                    // Filter results with confidence > threshold
                    let filteredResults = results.filter { $0.confidence > self.detectionStore.confidenceThreshold }
                    
                    // Create tracking requests for each detected object
                    self.trackingRequests = filteredResults.map { observation in
                        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                        request.trackingLevel = .accurate
                        return request
                    }
                    
                    // Update detections
                    self.detectionStore.detections = filteredResults.map { observation in
                        let topLabel = observation.labels[0]
                        return Detection(
                            id: observation.uuid,
                            boundingBox: observation.boundingBox,
                            label: topLabel.identifier,
                            confidence: topLabel.confidence
                        )
                    }
                    
                    // Store observations for tracking
                    for observation in filteredResults {
                        self.detectionStore.trackedObjects[observation.uuid] = observation
                    }
                }
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, 
                                        orientation: exifOrientationForCurrentDeviceOrientation(), 
                                        options: [:]).perform([request])
            } catch {
                print("Failed to perform detection: \(error)")
            }
        }

        private func performTracking(_ pixelBuffer: CVPixelBuffer) {
            do {
                try sequenceHandler.perform(trackingRequests, 
                                          on: pixelBuffer,
                                          orientation: exifOrientationForCurrentDeviceOrientation())
                
                // Process tracking results
                var newDetections: [Detection] = []
                var keepTracking = false
                
                for request in trackingRequests {
                    guard let result = request.results?.first as? VNDetectedObjectObservation else { continue }
                    
                    // Check if tracking is still reliable
                    if result.confidence > detectionStore.confidenceThreshold {
                        keepTracking = true
                        
                        // Update tracked object
                        detectionStore.trackedObjects[result.uuid] = result
                        
                        // Create new detection
                        if let originalDetection = detectionStore.detections.first(where: { $0.id == result.uuid }) {
                            newDetections.append(Detection(
                                id: result.uuid,
                                boundingBox: result.boundingBox,
                                label: originalDetection.label,
                                confidence: result.confidence
                            ))
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    // Update UI with new detections
                    if !newDetections.isEmpty {
                        self.detectionStore.detections = newDetections
                    }
                    
                    // If tracking confidence is low, restart detection
                    if !keepTracking {
                        self.trackingRequests.removeAll()
                    }
                }
            } catch {
                print("Failed to perform tracking: \(error)")
                trackingRequests.removeAll()
            }
        }

        func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
            let deviceOrientation = UIDevice.current.orientation

            switch deviceOrientation {
            case .portraitUpsideDown:
                return .left
            case .landscapeLeft:
                return .upMirrored
            case .landscapeRight:
                return .down
            case .portrait:
                return .up
            default:
                return .up
            }
        }
    }
}
