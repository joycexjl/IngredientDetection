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
    
    private var detectionOverlay: CALayer! = nil
    struct Detection {
        let boundingBox: CGRect
        let confidence: Float
        let classLabel: String
    }

    private var detectionTimer: Timer?
    private var isProcessingFrame = false
    
    // Vision parts
    internal var requests = [VNRequest]()
    
    // Add properties for timing control
    private var lastProcessingTime: TimeInterval = 0
    private let minimumTimeInterval: TimeInterval = 1.0  // One second between frames
    
    override func setupAVCapture() {
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
                        let detections = self.processYOLOOutput(multiArray)
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
        
        // 清除现有的检测层
        detectionOverlay.sublayers = nil
        let viewWidth = detectionOverlay.bounds.width
        let viewHeight = detectionOverlay.bounds.height
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
            boxLayer.borderColor = UIColor.green.cgColor
            boxLayer.backgroundColor = UIColor.clear.cgColor
            boxLayer.borderWidth = 3
            boxLayer.cornerRadius = 4
            
            // 创建标签图层
            let textLayer = createTextLayerInBounds(convertedBox,
                                                    identifier: detection.classLabel,
                                                    confidence: detection.confidence)

            // 添加图层
            detectionOverlay.addSublayer(boxLayer)
            detectionOverlay.addSublayer(textLayer)
        }
        
        CATransaction.commit()
        
        // updateLayerGeometry()
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        // Remove existing detection overlays
        self.detectionOverlay.sublayers = nil

        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            //—————————————————————— DEBUG ——————————————————————//
            print(observation)
            //—————————————————————— DEBUG ——————————————————————//

            // Select the label with the highest confidence
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox,
                                                            Int(self.bufferSize.width),
                                                            Int(self.bufferSize.height))

            // Create shape layer
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)

            // Create text layer
            let textLayer = self.createTextLayerInBounds(objectBounds,
                                                          identifier: topLabelObservation.identifier,
                                                          confidence: topLabelObservation.confidence)

            shapeLayer.addSublayer(textLayer)
            self.detectionOverlay.addSublayer(shapeLayer)
        }

        self.updateLayerGeometry()
    }

    func applyNMS(_ boxes: [Detection], iouThreshold: Float = 0.45) -> [Detection] {
        var selected: [Detection] = []
        
        // 只处理置信度排序后的前100个框
        for detection in boxes.prefix(100) {
            var shouldSelect = true
            
            // 检查是否与已选择的框重叠
            for selectedBox in selected {
                let iou = calculateIOU(detection.boundingBox, selectedBox.boundingBox)
                if iou > iouThreshold {
                    // 如果重叠度高，且当前框置信度更高，替换已选择的框
                    if detection.confidence > selectedBox.confidence {
                        if let index = selected.firstIndex(where: { $0.boundingBox == selectedBox.boundingBox }) {
                            selected[index] = detection
                            shouldSelect = false
                            break
                        }
                    } else {
                        shouldSelect = false
                        break
                    }
                }
            }
            
            if shouldSelect {
                selected.append(detection)
            }
            
            // 如果已经选择了足够多的框，就停止处理
            if selected.count >= 5 {
                break
            }
        }
        return selected
    }

    
    func processYOLOOutput(_ multiArray: MLMultiArray) -> [Detection] {
        var detections: [Detection] = []
        let numClasses = 80  // 根据你的模型调整
        let numAttributes = numClasses + 4  // 类别数 + 边界框坐标
        let numBoxes = 8400

        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        var classScores = [Float](repeating: 0, count: numClasses)
        var maxScore: Float = 0
        var maxIndex: vDSP_Length = 0
        var boundingBoxes: [Detection] = []
        boundingBoxes.reserveCapacity(100)  // 预估容量

        // for all boxes
        for i in 0..<numBoxes {  // 根据你的模型调整
            // 找出最高置信度的类别
            for j in 0..<numClasses {
                classScores[j] = dataPointer[4 * numBoxes + j * numBoxes + i]
            }

            // find max score and index
            vDSP_maxvi(classScores,
                  vDSP_Stride(1),
                  &maxScore,
                  &maxIndex,
                  vDSP_Length(numClasses))

            // 如果置信度超过阈值
            if maxScore > 0.5 {  // 根据需要调整阈值
                // 获取边界框坐标
                let x = Float(truncating: multiArray[[0, 0, i] as [NSNumber]])
                let y = Float(truncating: multiArray[[0, 1, i] as [NSNumber]])
                let w = Float(truncating: multiArray[[0, 2, i] as [NSNumber]])
                let h = Float(truncating: multiArray[[0, 3, i] as [NSNumber]])
                // 归一化坐标 (确保所有值在0-1之间)
                let normalizedX = CGFloat(x) / 640.0  // 模型输入宽度
                let normalizedY = CGFloat(y) / 640.0  // 模型输入高度
                let normalizedW = CGFloat(w) / 640.0
                let normalizedH = CGFloat(h) / 640.0
                
                // 创建边界框，注意中心点坐标转换为左上角坐标
                let boundingBox = CGRect(
                    x: max(0, min(1, normalizedX - normalizedW/2)),
                    y: max(0, min(1, normalizedY - normalizedH/2)),
                    width: max(0, min(1, normalizedW)),
                    height: max(0, min(1, normalizedH))
                )

                detections.append(Detection(boundingBox: boundingBox,
                                         confidence: maxScore,
                                         classLabel: getClassLabel(Int(maxIndex))))
            }
        }
        
        print("detected \(detections.count) objects")
        return applyNMS(detections.sorted { $0.confidence > $1.confidence })
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
    
    func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        let union = box1.union(box2)
        
        guard !intersection.isNull && !union.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = union.width * union.height
        
        return Float(intersectionArea / unionArea)
    }

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
