//
//  ControllerView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/5/24.
//

import UIKit
import AVFoundation
import Vision
import CoreML
import Accelerate

class VisionObjectRecognitionViewController: ViewController {
    
    var detectionOverlay: CALayer! = nil

    private lazy var detectionProcessor: DetectionResultProcessor = {
        let processor = DetectionResultProcessor()
        processor.delegate = self
        print("🔄 Creating DetectionResultProcessor and setting delegate")
        return processor
    }()

    var detectionTimer: Timer?
    var isProcessingFrame = false
    
    // Vision parts
    internal var requests = [VNRequest]()
    
    // Add properties for timing control
    private var lastProcessingTime: TimeInterval = 0
    private let minimumTimeInterval: TimeInterval = 1.0  // One second between frames
    
    override func setupAVCapture() {
        // Set background color
        view.backgroundColor = UIColor(red: 54/255, green: 94/255, blue: 50/255, alpha: 0.93)
        
        // Setup preview view constraints
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Call super setup
        super.setupAVCapture()
        
        // Set up vision components
        setupLayers()
        updateLayerGeometry()
        setupVision()
    }
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        
        // Check if enough time has passed since last processing
        guard (currentTime - lastProcessingTime) >= minimumTimeInterval else {
            return  // Skip this frame if not enough time has passed
        }
        
        // Process frame and update last processing time
        processCurrentFrame(sampleBuffer: sampleBuffer)
        lastProcessingTime = currentTime
    }
    
    func processCurrentFrame() {
        // Default implementation for camera processing
        // This will be overridden by VideoViewController for video processing
    }
    
    func processCurrentFrame(sampleBuffer: CMSampleBuffer) {
        // If already processing a frame, skip this one
        guard !isProcessingFrame else {
            // print("Skipping frame - still processing previous frame")
            return
        }
        
        // Mark processing started
        isProcessingFrame = true
        // print("Processing new frame at time: \(CACurrentMediaTime())")
        
        // Get pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            // print("Failed to get pixel buffer")
            isProcessingFrame = false
            return
        }
        
        // Process current frame
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            // print("Failed to process video frame: \(error)")
        }
        
        // Mark processing complete
        isProcessingFrame = false
    }
    
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        do {
            // print("setupVision")
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            guard let model = try? new_11s(configuration: config) else {
                // print("Failed to create model instance")
                fatalError("Failed to create model instance")
            }
            
            let visionModel = try VNCoreMLModel(for: model.model)
            
            let objectRecognition = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if let results = request.results as? [VNCoreMLFeatureValueObservation],
                       let observation = results.first,
                       let multiArray = observation.featureValue.multiArrayValue {
                        // print("multiArray: ", multiArray)
                        // multiArray:  Float32 1 × 84 × 8400 array
                        
                        self.setupLayers()
                        // 理 YOLO 输出并直接绘制
                        let detections = self.detectionProcessor.processMLMultiArray(multiArray)
                        self.drawDetections(detections)
                    }
                }
            }
            self.requests = [objectRecognition]
            
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
        return error
    }
    
    func drawDetections(_ detections: [Detection]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)

        let safeAreaInsets = view.safeAreaInsets // eaaaaaaaaaaaaa
        
        // Remove current overlays
        detectionOverlay.sublayers = nil
        let viewWidth = detectionOverlay.bounds.width - safeAreaInsets.left - safeAreaInsets.right
        let viewHeight = detectionOverlay.bounds.height - safeAreaInsets.bottom - safeAreaInsets.top
        detectionOverlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // get top 5 detections
        for detection in detections {
            // print("start drawing detections")
            // print(detection)  // TODO
            let convertedBox = CGRect(
                x: detection.boundingBox.minX * viewWidth,
                y: detection.boundingBox.minY * viewHeight,
                width: detection.boundingBox.width * viewWidth,
                height: detection.boundingBox.height * viewHeight
            )

            // detection bounding box
            let boxLayer = CALayer()
            boxLayer.frame = convertedBox
//            boxLayer.borderColor = UIColor.green.cgColor
            boxLayer.borderColor = Constants.category(for: detection.classLabel).cgColor
            boxLayer.backgroundColor = UIColor.clear.cgColor
            boxLayer.borderWidth = 3
            boxLayer.cornerRadius = 4
            
            // label
            let textLayer = createTextLayerInBounds(convertedBox,
                                                    identifier: detection.classLabel,
                                                    confidence: detection.confidence)

            // add overlay
            detectionOverlay.addSublayer(boxLayer)
            detectionOverlay.addSublayer(textLayer)
        }
        
        CATransaction.commit()
        
        // updateLayerGeometry()
    }
    
    func setupLayers() {
        // Remove existing detection overlay if it exists
        detectionOverlay?.removeFromSuperlayer()
        
        // Create new detection overlay
        detectionOverlay = CALayer()
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                       y: 0.0,
                                       width: bufferSize.width,
                                       height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }

    func updateLayerGeometry() {
        let bounds = self.rootLayer.bounds
        // var scale: CGFloat = 1.0
        let scale = bounds.size.width / view.bounds.size.width
        _ = CGAffineTransform(scaleX: scale, y: scale)
        self.detectionOverlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))
        self.detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    func createTextLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        let labelText = String(format: "%@ %.1f%%", identifier, confidence * 100)
        textLayer.string = labelText
        textLayer.font = UIFont(name: "Jost", size: 14)
        textLayer.fontSize = 14
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = UIColor(red: 54/255, green: 94/255, blue: 50/255, alpha: 0.8).cgColor
        textLayer.alignmentMode = .center
        textLayer.cornerRadius = 5
        textLayer.masksToBounds = true
        
        let textWidth = (labelText as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: 20)
            ]).width + 20

        textLayer.frame = CGRect(
            x: bounds.minX,
            y: max(0, bounds.minY - 20),  // 确保不会超出屏幕顶部
            width: min(textWidth, bounds.width),
            height: 20
        )
        textLayer.contentsScale = UIScreen.main.scale
        return textLayer
    }

    @objc override func showAddIngredientAlert(for foodItem: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Add Ingredient",
                message: "How many \(foodItem)(s) would you like to add?",
                preferredStyle: .alert
            )
            
            // Style the alert
            alert.view.tintColor = UIColor(red: 54/255, green: 94/255, blue: 50/255, alpha: 1)
            
            // Style the text field
            alert.addTextField { textField in
                textField.keyboardType = .numberPad
                textField.placeholder = "Enter quantity"
                textField.font = UIFont(name: "Jost", size: 16)
            }
            
            let addAction = UIAlertAction(title: "Add", style: .default) { [weak self] _ in
                guard let self = self,
                      let quantityText = alert.textFields?.first?.text,
                      let quantity = Int(quantityText), quantity > 0 else {
                    self?.showErrorAlert(message: "Please enter a valid quantity")
                    return
                }
                
                print("📱 Adding ingredient: \(foodItem) with quantity: \(quantity)")
                self.addIngredient(name: foodItem, quantity: quantity)
                self.detectionProcessor.markIngredientAsAdded(foodItem)
            }
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
            
            alert.addAction(addAction)
            alert.addAction(cancelAction)
            
            self.present(alert, animated: true)
        }
    }

    private func showErrorAlert(message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Error",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    private func addIngredient(name: String, quantity: Int) {
        // Assuming each row is 60 points high and we have 10 points padding
        let maxVisibleRows = Int(floor((200 - 20) / 60)) // 200 is table height, 20 is total padding
        
        if ingredientsList.count < maxVisibleRows {
            ingredientsList.append((name: name, quantity: quantity))
            ingredientsTableView.reloadData()
        } else {
            showErrorAlert(message: "Maximum ingredients reached. Please delete some items first.")
        }
    }
}
