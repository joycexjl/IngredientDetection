//
//  ControllerView.swift
//  IngredientDetection
//
//  Created by Joyce Liu on 11/5/24.
//

import UIKit
import AVFoundation
import Vision

class VisionObjectRecognitionViewController: ViewController {
    
    private var detectionOverlay: CALayer! = nil
    struct Detection {
        let boundingBox: CGRect
        let confidence: Float
        let classLabel: String
        let color: CGColor
    }
    
    // Vision parts
    internal var requests = [VNRequest]()
    
    override func setupAVCapture() {
        print("VisionObjectRecognitionViewController - setupAVCapture started")
        super.setupAVCapture()
        
        print("VisionObjectRecognitionViewController - Setting up Vision components")
        setupLayers()
        updateLayerGeometry()
        setupVision()
        print("VisionObjectRecognitionViewController - Vision setup complete")
    }
    
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            guard let model = try? yolo11m(configuration: config) else {
                fatalError("Failed to create model instance")
            }

            let visionModel = try VNCoreMLModel(for: model.model)
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
//                        print("VisionObjectRecognitionViewController - Drawing \(results.count) results")
                        // —————————————————————— DEBUG —————————————————————— //
//                         print("raw results: ", results) // 打印原始结果

                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
            print("VisionObjectRecognitionViewController - Vision setup completed successfully")
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }

    
    
    func drawVisionRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        
        // Process Vision results
        if let observation = results.first as? VNCoreMLFeatureValueObservation,
           let multiArray = observation.featureValue.multiArrayValue {
            print("Processing YOLO output with shape: \(multiArray.shape)")
            
            let detections = processYOLOOutput(multiArray)
            
            // Draw each detection
            for detection in detections {
                let objectBounds = VNImageRectForNormalizedRect(detection.boundingBox, 
                                                              Int(bufferSize.width), 
                                                              Int(bufferSize.height))
                
                let shapeLayer = createRoundedRectLayerWithBounds(objectBounds, color: detection.color)
                let textLayer = createTextSubLayerInBounds(objectBounds,
                                                         identifier: detection.classLabel,
                                                         confidence: detection.confidence)
                
                shapeLayer.addSublayer(textLayer)
                detectionOverlay.addSublayer(shapeLayer)
            }
        }
        
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func processYOLOOutput(_ multiArray: MLMultiArray) -> [Detection] {
        var detections: [Detection] = []
        let numClasses = 80
        
        // Process each of the 8400 predictions
        for i in 0..<8400 {
            var maxClassScore: Float = 0
            var maxClassIndex = 0
            
            // Find the class with highest confidence
            for j in 0..<numClasses {
                let score = Float(truncating: multiArray[[0, 4 + j, i] as [NSNumber]])
                if score > maxClassScore {
                    maxClassScore = score
                    maxClassIndex = j
                }
            }
            
            // If confidence exceeds threshold
            if maxClassScore > 0.25 {  // Adjust threshold as needed
                // Get bounding box coordinates
                let x = Float(truncating: multiArray[[0, 0, i] as [NSNumber]])
                let y = Float(truncating: multiArray[[0, 1, i] as [NSNumber]])
                let w = Float(truncating: multiArray[[0, 2, i] as [NSNumber]])
                let h = Float(truncating: multiArray[[0, 3, i] as [NSNumber]])
                
                // Convert to normalized coordinates
                let boundingBox = CGRect(x: CGFloat(x - w/2),
                                       y: CGFloat(y - h/2),
                                       width: CGFloat(w),
                                       height: CGFloat(h))
                
                let classLabel = getClassLabel(maxClassIndex)
                // ------------------ DEBUG ------------------ //
                print(classLabel)
                let color = getColorForCategory(classLabel)
                
                detections.append(Detection(boundingBox: boundingBox,
                                         confidence: maxClassScore,
                                         classLabel: classLabel,
                                            color: color.cgColor))
            }
        }
        
//        print("Detected \(detections.count) objects")
        return detections
    }
    
    func getClassLabel(_ index: Int) -> String {
        let labels = ["person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
                     "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
                     "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
                     "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
                     "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
                     "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
                     "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
                     "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
                     "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
                     "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"]
        return index < labels.count ? labels[index] : "unknown"
    }
    

   func getColorForCategory(_ label: String) -> UIColor {
       // Define category groups
       let people = ["person"]
       let vehicles = ["bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat"]
       let animals = ["bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"]
       let food = ["banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake"]
       
       // Return different colors based on category
       switch label {
       case _ where people.contains(label):
           return UIColor.red
       case _ where vehicles.contains(label):
           return UIColor.blue
       case _ where animals.contains(label):
           return UIColor.green
       case _ where food.contains(label):
           return UIColor.orange
       default:
           return UIColor.yellow
       }
   }

    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect, color: CGColor? = nil) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = color ?? CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.4)
        shapeLayer.cornerRadius = 7
        shapeLayer.borderColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8)
        shapeLayer.borderWidth = 2
        return shapeLayer
    }
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("VisionObjectRecognitionViewController - Processing new frame")
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("VisionObjectRecognitionViewController - Failed to get pixel buffer")
            return
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientationFromDeviceOrientation(), options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
//            print("VisionObjectRecognitionViewController - Vision requests performed successfully")
        } catch {
            print("VisionObjectRecognitionViewController - Failed to perform image request: \(error)")
        }
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
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
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
}
