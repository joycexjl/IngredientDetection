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
    // struct Detection {
    //     let boundingBox: CGRect
    //     let confidence: Float
    //     let classLabel: String
    // }
    private let detectionProcessor = DetectionResultProcessor()

    var detectionTimer: Timer?
    var isProcessingFrame = false
    
    // Vision parts
    internal var requests = [VNRequest]()
    
    // Add properties for timing control
    private var lastProcessingTime: TimeInterval = 0
    private let minimumTimeInterval: TimeInterval = 1.0  // One second between frames
    
    override func setupAVCapture() {
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
        
        print("VisionObjectRecognitionViewController - setupAVCapture started")
        super.setupAVCapture()
        
        print("VisionObjectRecognitionViewController - Setting up Vision components")
        setupLayers()
        updateLayerGeometry()
        setupVision()
        print("VisionObjectRecognitionViewController - Vision setup complete")
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
            print("Skipping frame - still processing previous frame")
            return 
        }
        
        // Mark processing started
        isProcessingFrame = true
        print("Processing new frame at time: \(CACurrentMediaTime())")
        
        // Get pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get pixel buffer")
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
            print("Failed to process video frame: \(error)")
        }
        
        // Mark processing complete
        isProcessingFrame = false
    }
    
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        do {
            print("setupVision")
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            guard let model = try? yolo11m(configuration: config) else {
                print("Failed to create model instance")
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
                        // 处理 YOLO 输出并直接绘制
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
            print("start drawing detections")
            print(detection)  // TODO
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
    
//     func drawVisionRequestResults(_ results: [Any]) {
//         // Remove existing detection overlays
//         self.detectionOverlay.sublayers = nil

//         for observation in results where observation is VNRecognizedObjectObservation {
//             guard let objectObservation = observation as? VNRecognizedObjectObservation else {
//                 continue
//             }
//             //—————————————————————— DEBUG ——————————————————————//
//             print(observation)
//             //—————————————————————— DEBUG ——————————————————————//

//             // Select the label with the highest confidence
//             let topLabelObservation = objectObservation.labels[0]
//             let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox,
//                                                             Int(self.bufferSize.width),
//                                                             Int(self.bufferSize.height))

//             // Create shape layer
//             let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)

//             // Create text layer
//             let textLayer = self.createTextLayerInBounds(objectBounds,
//                                                           identifier: topLabelObservation.identifier,
//                                                           confidence: topLabelObservation.confidence)

//             shapeLayer.addSublayer(textLayer)
//             self.detectionOverlay.addSublayer(shapeLayer)
//         }

//         self.updateLayerGeometry()
//     }

//     func applyNMS(_ boxes: [Detection], iouThreshold: Float = 0.45) -> [Detection] {
//         var selected: [Detection] = []
        
//         // 只处理置信度排序后的前100个框
//         for detection in boxes.prefix(100) {
//             var shouldSelect = true
            
//             // 检查是否与已选择的框重叠
//             for selectedBox in selected {
//                 let iou = calculateIOU(detection.boundingBox, selectedBox.boundingBox)
//                 if iou > iouThreshold {
//                     // 如果重叠度高，且当前框置信度更高，替换已选择的框
//                     if detection.confidence > selectedBox.confidence {
//                         if let index = selected.firstIndex(where: { $0.boundingBox == selectedBox.boundingBox }) {
//                             selected[index] = detection
//                             shouldSelect = false
//                             break
//                         }
//                     } else {
//                         shouldSelect = false
//                         break
//                     }
//                 }
//             }
            
//             if shouldSelect {
//                 selected.append(detection)
//             }
            
//             // 如果已经选择了足够多的框，就停止处理
//             if selected.count >= 5 {
//                 break
//             }
//         }
//         return selected
//     }
    
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
    
    // func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
    //     let intersection = box1.intersection(box2)
    //     let union = box1.union(box2)
        
    //     guard !intersection.isNull && !union.isNull else { return 0 }
    //     let intersectionArea = intersection.width * intersection.height
    //     let unionArea = union.width * union.height
        
    //     return Float(intersectionArea / unionArea)
    // }

    func updateLayerGeometry() {
        let bounds = self.rootLayer.bounds
        // var scale: CGFloat = 1.0
        let scale = bounds.size.width / view.bounds.size.width
        let transform = CGAffineTransform(scaleX: scale, y: scale) 
        self.detectionOverlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))
        self.detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    func createTextLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        let labelText = String(format: "%@ %.1f%%",
                        identifier,
                        confidence * 100)
        textLayer.string = labelText    
        textLayer.fontSize = 14
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = UIColor.black.cgColor
        textLayer.alignmentMode = .center
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.width, height: 20)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.minY - 10)

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
}
