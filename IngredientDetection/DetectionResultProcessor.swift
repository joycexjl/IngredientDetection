import UIKit
import CoreML
import Vision
import Accelerate


// MARK: - Models
struct Detection {
    let boundingBox: CGRect
    let confidence: Float
    let classLabel: String
}


// MARK: - Constants
enum Constants {
    static let numBoxes = 8400
    static let modelInputSize: CGFloat = 640.0
    static let defaultConfidenceThreshold: Float = 0.2
    static let defaultMaxDetections = 10
    static let defaultIOUThreshold: Float = 0.45
    
    static let people = Set(["person"])
    static let vehicles = Set(["bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat"])
    static let animals = Set(["bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"])
    static let food = Set(["banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake"])
       
    static let classLabels = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
        "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]
    
    static func category(for label: String) ->  UIColor  {
        assert(classLabels.contains(label), "Label '\(label)' not found in classLabels")
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
    
    static let foodDetectionThreshold: TimeInterval = 2.0
}

// Add new protocol for delegate
@objc protocol DetectionResultProcessorDelegate: AnyObject {
    func showAddIngredientAlert(for foodItem: String)
}

// MARK: - DetectionResultProcessor
class DetectionResultProcessor {
    // MARK: - Properties
    private let confidenceThreshold: Float
    private let maxDetections: Int
    private let iouThreshold: Float
    
    private var lastFoodDetectionTimes: [String: Date] = [:]
    private var addedIngredients: Set<String> = []
    weak var delegate: DetectionResultProcessorDelegate? {
        didSet {
            print("🔄 Delegate set: \(delegate != nil ? "YES" : "NO")")
        }
    }
    
    // Add a property to track if we've already shown an alert for the current detection
    private var alertShownForCurrentDetection: [String: Bool] = [:]
    
    // MARK: - Initialization
    init(confidenceThreshold: Float = Constants.defaultConfidenceThreshold,
         maxDetections: Int = Constants.defaultMaxDetections,
         iouThreshold: Float = Constants.defaultIOUThreshold) {
        self.confidenceThreshold = confidenceThreshold
        self.maxDetections = maxDetections
        self.iouThreshold = iouThreshold
    }
    
    // MARK: - Public Methods
    func processMLMultiArray(_ multiArray: MLMultiArray) -> [Detection] {
        let rawDetections = extractDetections(from: multiArray)
        let filteredDetections = filterDetections(rawDetections)
        let nmsDetections = applyNMS(to: filteredDetections)
        
        // Process food detections
        checkSustainedFoodDetections(in: nmsDetections)
        
        // Filter out already added ingredients
        return nmsDetections.filter { !addedIngredients.contains($0.classLabel) }
    }
    
    // MARK: - extract Detections from MLMultiArray
    private func extractDetections(from multiArray: MLMultiArray) -> [Detection] {
        let dataPointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)

        var classScores = [Float](repeating: 0, count: Constants.classLabels.count)
        var detections: [Detection] = []
        detections.reserveCapacity(100)
        
        for i in 0..<Constants.numBoxes {
            guard let detection = processBox(at: i, dataPointer: dataPointer, classScores: &classScores) else { continue }
            detections.append(detection)
        }
        
        return detections
    }
    
    private func processBox(at index: Int, dataPointer: UnsafePointer<Float>, classScores: inout [Float]) -> Detection? {
        // 提取类别分数
        for (classIndex, _) in Constants.classLabels.enumerated() {
            classScores[classIndex] = dataPointer[4 * Constants.numBoxes + classIndex * Constants.numBoxes + index]
        }
        
        // 找出最高置信度的类别
        var maxScore: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(classScores,
                   vDSP_Stride(1),
                   &maxScore,
                   &maxIndex,
                   vDSP_Length(Constants.classLabels.count))
        
        // 检查置信度阈值
        guard maxScore > confidenceThreshold else { return nil }
        
        // 提取边界框坐标
        let boundingBox = extractBoundingBox(at: index, from: dataPointer)
        
        return Detection(
            boundingBox: boundingBox,
            confidence: maxScore,
            classLabel: Constants.classLabels[Int(maxIndex)]
        )
    }
    
    private func extractBoundingBox(at index: Int, from dataPointer: UnsafePointer<Float>) -> CGRect {
        let x = CGFloat(dataPointer[0 * Constants.numBoxes + index])
        let y = CGFloat(dataPointer[1 * Constants.numBoxes + index])
        let w = CGFloat(dataPointer[2 * Constants.numBoxes + index])
        let h = CGFloat(dataPointer[3 * Constants.numBoxes + index])
        
        // 归一化坐标
        return CGRect(
            x: max(0, min(1, (x / Constants.modelInputSize) - (w / Constants.modelInputSize) / 2)),
            y: max(0, min(1, (y / Constants.modelInputSize) - (h / Constants.modelInputSize) / 2)),
            width: max(0, min(1, w / Constants.modelInputSize)),
            height: max(0, min(1, h / Constants.modelInputSize))
        )
    }
    
    private func filterDetections(_ detections: [Detection]) -> [Detection] {
        return detections
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxDetections)
            .map { $0 } 
    }
    
    private func applyNMS(to detections: [Detection]) -> [Detection] {
        var result: [Detection] = []
        
        for detection in detections {
            var shouldSelect = true
            
            for selectedDetection in result {
                let iou = calculateIOU(detection.boundingBox, selectedDetection.boundingBox)
                if iou > iouThreshold {
                    shouldSelect = false
                    break
                }
            }
            
            if shouldSelect {
                result.append(detection)
            }
            
            if result.count >= maxDetections {
                break
            }
        }
        
        return result
    }
    
    private func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        let union = box1.union(box2)
        
        guard !intersection.isNull && !union.isNull else { return 0 }
        
        return Float(intersection.area / union.area)
    }
    
    // Add new method to track food detections
    private func checkSustainedFoodDetections(in detections: [Detection]) {
        let currentTime = Date()
        
        print("\n--- Starting Food Detection Check ---")
        print("🎯 Delegate exists: \(delegate != nil ? "YES" : "NO")")
        print("Currently visible detections:", detections.map { "\($0.classLabel) (conf: \($0.confidence))" })
        print("Current food tracking state:")
        print("- Last detection times:", lastFoodDetectionTimes)
        print("- Alert shown state:", alertShownForCurrentDetection)
        print("- Added ingredients:", addedIngredients)
        
        // Update detection times for currently visible food items
        for detection in detections where Constants.food.contains(detection.classLabel) {
            let foodItem = detection.classLabel
            
            if !addedIngredients.contains(foodItem) {
                if lastFoodDetectionTimes[foodItem] == nil {
                    print("➡️ First time seeing \(foodItem), starting timer")
                    lastFoodDetectionTimes[foodItem] = currentTime
                    alertShownForCurrentDetection[foodItem] = false
                }
                
                if let detectionStart = lastFoodDetectionTimes[foodItem] {
                    let timeVisible = currentTime.timeIntervalSince(detectionStart)
                    print("📍 \(foodItem) has been visible for \(String(format: "%.1f", timeVisible))s")
                    
                    if timeVisible >= Constants.foodDetectionThreshold {
                        if alertShownForCurrentDetection[foodItem] == false {
                            print("🔔 Attempting to show alert for \(foodItem)")
                            if let delegate = delegate {
                                delegate.showAddIngredientAlert(for: foodItem)
                                alertShownForCurrentDetection[foodItem] = true
                                print("✅ Alert delegate method called")
                            } else {
                                print("❌ ERROR: Delegate is nil! Alert cannot be shown")
                            }
                        } else {
                            print("⏭️ Alert already shown for \(foodItem)")
                        }
                    } else {
                        print("⏳ Waiting for \(foodItem) - \(String(format: "%.1f", Constants.foodDetectionThreshold - timeVisible))s remaining")
                    }
                }
            } else {
                print("⚠️ \(foodItem) already in ingredients list - ignoring")
            }
        }
        
        // Clear detection times and alert flags for food items no longer visible
        let visibleFoodItems = Set(detections.map { $0.classLabel })
        for foodItem in lastFoodDetectionTimes.keys where !visibleFoodItems.contains(foodItem) {
            print("❌ \(foodItem) no longer visible - resetting tracking")
            lastFoodDetectionTimes.removeValue(forKey: foodItem)
            alertShownForCurrentDetection.removeValue(forKey: foodItem)
        }
        
        print("--- End Food Detection Check ---\n")
    }
    
    // Add method to mark ingredient as added
    func markIngredientAsAdded(_ ingredient: String) {
        addedIngredients.insert(ingredient)
        lastFoodDetectionTimes.removeValue(forKey: ingredient)
    }
    
    // Add to DetectionResultProcessor class
    func unmarkIngredientAsAdded(_ ingredient: String) {
        addedIngredients.remove(ingredient)
    }
}

// MARK: - CGRect Extension
private extension CGRect {
    var area: CGFloat {
        return width * height
    }
}
