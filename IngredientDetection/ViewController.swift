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

class ViewController: UIViewController {

    // MARK: - Properties

    var previewLayer: AVCaptureVideoPreviewLayer!
    var captureSession: AVCaptureSession!
    let videoDataOutput = AVCaptureVideoDataOutput()
    let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
    var bufferSize: CGSize = .zero

    var rootLayer: CALayer! = nil

    // Vision and Core ML
    private var requests = [VNRequest]()
    private var detectionOverlay: CALayer! = nil

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up camera
        setupAVCapture()

        // Set up Vision model
        setupVision()

        // Set up detection overlay
        setupLayers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Start the capture session
        captureSession.startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop the capture session
        captureSession.stopRunning()
    }

    // MARK: - Camera Setup

    func setupAVCapture() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .vga640x480 // Adjust as needed

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            fatalError("Could not find a back camera.")
        }

        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            fatalError("Could not create video device input.")
        }

        guard captureSession.canAddInput(deviceInput) else {
            fatalError("Could not add video device input to the session.")
        }
        captureSession.addInput(deviceInput)

        // Add video output
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)

            // Configure your output.
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        } else {
            fatalError("Could not add video data output to the session.")
        }

        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true

        do {
            try videoDevice.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice.unlockForConfiguration()
        } catch {
            print(error)
        }

        // Set up preview layer
        setupPreviewLayer()
    }

    func setupPreviewLayer() {
        // Set up preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        rootLayer = self.view.layer
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
    }

    // MARK: - Vision Setup

    func setupVision() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Changed from cpuAndGPU to all
            
            // Get the URL for the model in the app bundle
            guard let modelURL = Bundle.main.url(forResource: "yolo11x", withExtension: "mlpackage") else {
                fatalError("Failed to find model file in bundle")
            }
            
            // Compile the model
            let compiledModelURL = try MLModel.compileModel(at: modelURL)
            let model = try MLModel(contentsOf: compiledModelURL)
            
            let visionModel = try VNCoreMLModel(for: model)
            
            // Create request
            let objectRecognition = VNCoreMLRequest(model: visionModel) { request, error in
                DispatchQueue.main.async {
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                }
            }
            objectRecognition.imageCropAndScaleOption = .scaleFill
            self.requests = [objectRecognition]
            
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }

    // MARK: - Drawing Detection Results

    func setupLayers() {
        detectionOverlay = CALayer() // Container layer for all the detection overlays
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }

    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scaleX: CGFloat
        var scaleY: CGFloat

        // Calculate scale factors to fit the detection overlay within the preview layer
        if let previewLayerConnection = previewLayer.connection {
            switch previewLayerConnection.videoOrientation {
            case .portrait, .portraitUpsideDown:
                scaleX = bounds.size.width / bufferSize.height
                scaleY = bounds.size.height / bufferSize.width
            default:
                scaleX = bounds.size.width / bufferSize.width
                scaleY = bounds.size.height / bufferSize.height
            }

            // Apply transformations
            let scale = max(scaleX, scaleY)
            detectionOverlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))
            detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    func drawVisionRequestResults(_ results: [Any]) {
        // Remove existing detection overlays
        detectionOverlay.sublayers = nil

        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }

            // Select the label with the highest confidence
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox,
                                                            Int(bufferSize.width),
                                                            Int(bufferSize.height))

            // Create shape layer
            let shapeLayer = createRoundedRectLayerWithBounds(objectBounds)

            // Create text layer
            let textLayer = createTextLayerInBounds(objectBounds,
                                                    identifier: topLabelObservation.identifier,
                                                    confidence: topLabelObservation.confidence)

            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }

        updateLayerGeometry()
    }

    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.backgroundColor = UIColor.clear.cgColor
        shapeLayer.borderColor = UIColor.red.cgColor
        shapeLayer.borderWidth = 2.0
        shapeLayer.cornerRadius = 4.0

        return shapeLayer
    }

    func createTextLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.string = "\(identifier) \(String(format: "%.1f", confidence * 100))%"
        textLayer.fontSize = 14
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        textLayer.alignmentMode = .center
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.width, height: 20)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.minY - 10)

        return textLayer
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Get the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Get the device orientation
        let exifOrientation = exifOrientationForCurrentDeviceOrientation()

        // Create image request handler
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                        orientation: exifOrientation,
                                                        options: [:])

        // Perform Vision request
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print("Failed to perform image request: \(error)")
        }
    }

    // Helper function to get Exif orientation
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
