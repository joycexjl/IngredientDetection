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

        // Initialize rootLayer first
        rootLayer = self.view.layer

        // Then set up other components
        setupAVCapture()

        // Set up Vision model
        setupVision()

        // Set up detection overlay
        setupLayers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Start the capture session in background thread
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop the capture session in background thread
        DispatchQueue.global(qos: .background).async {
            self.captureSession.stopRunning()
        }
    }

    // MARK: - Camera Setup

    func setupAVCapture() {
        // Move the entire setup to a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession = AVCaptureSession()
            self.captureSession.sessionPreset = .vga640x480
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                fatalError("Could not find a back camera.")
            }
            
            guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                fatalError("Could not create video device input.")
            }
            
            guard self.captureSession.canAddInput(deviceInput) else {
                fatalError("Could not add video device input to the session.")
            }
            self.captureSession.addInput(deviceInput)
            
            // Add video output
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                
                // Configure your output.
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            } else {
                fatalError("Could not add video data output to the session.")
            }
            
            let captureConnection = self.videoDataOutput.connection(with: .video)
            captureConnection?.isEnabled = true
            
            do {
                try videoDevice.lockForConfiguration()
                let dimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription)
                self.bufferSize.width = CGFloat(dimensions.width)
                self.bufferSize.height = CGFloat(dimensions.height)
                videoDevice.unlockForConfiguration()
            } catch {
                print(error)
            }
            
            // Update UI elements on main thread
            DispatchQueue.main.async {
                self.setupPreviewLayer()
            }
        }
    }

    func setupPreviewLayer() {
        // Set up preview layer
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer.videoGravity = .resizeAspectFill

        self.rootLayer = self.view.layer
        self.previewLayer.frame = self.rootLayer.bounds
        self.rootLayer.addSublayer(self.previewLayer)
    }

    // MARK: - Vision Setup

    func setupVision() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            guard let model = try? yolo11m(configuration: config) else {
                fatalError("Failed to create model instance")
            }
            
            let visionModel = try VNCoreMLModel(for: model.model)
            
            let objectRecognition = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if let results = request.results as? [VNCoreMLFeatureValueObservation],
                       let observation = results.first,
                       let multiArray = observation.featureValue.multiArrayValue {
                        // —————————————————————— DEBUG —————————————————————— //
                        // print("raw results: ", results) // 打印原始结果
                        // —————————————————————— DEBUG —————————————————————— //
                        
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
    }

    // MARK: - Drawing Detection Results

    func setupLayers() {
        // Make sure rootLayer is initialized
        if rootLayer == nil {
            rootLayer = self.view.layer
        }
        
        self.detectionOverlay = CALayer()
        self.detectionOverlay.name = "DetectionOverlay"
        self.detectionOverlay.bounds = CGRect(x: 0.0,
                                             y: 0.0,
                                             width: self.bufferSize.width,
                                             height: self.bufferSize.height)
        
        // Add null check before accessing rootLayer
        guard let rootLayer = self.rootLayer else {
            print("Root layer is not initialized")
            return
        }
        
        self.detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(self.detectionOverlay)
    }
    
    func drawDetections(_ detections: [Detection]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // 清除现有的检测层
        detectionOverlay.sublayers = nil
        
        for detection in detections {
            // 创建边界框图层
            let boxLayer = CALayer()
            boxLayer.bounds = detection.boundingBox
            boxLayer.position = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
            boxLayer.borderColor = UIColor.red.cgColor
            boxLayer.borderWidth = 2
            boxLayer.cornerRadius = 4
            
            // 创建标签图层
            let textLayer = CATextLayer()
            textLayer.string = String(format: "%@ %.1f%%",
                                    detection.classLabel,
                                    detection.confidence * 100)
            textLayer.fontSize = 14
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
            textLayer.cornerRadius = 4
            textLayer.alignmentMode = .center
            textLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 20)
            textLayer.position = CGPoint(x: detection.boundingBox.midX,
                                       y: detection.boundingBox.minY - 10)
            
            // 添加图层
            detectionOverlay.addSublayer(boxLayer)
            detectionOverlay.addSublayer(textLayer)
        }
        
        CATransaction.commit()
        
        updateLayerGeometry()
    }
    
    struct Detection {
        let boundingBox: CGRect
        let confidence: Float
        let classLabel: String
    }

    func processYOLOOutput(_ multiArray: MLMultiArray) -> [Detection] {
        // —————————————————————— DEBUG —————————————————————— //
        // print("处理 YOLO 输出，维度：", multiArray.shape)
        // —————————————————————— DEBUG —————————————————————— //
        
        var detections: [Detection] = []
        let numClasses = 80  // 根据你的模型调整
        let numAttributes = numClasses + 4  // 类别数 + 边界框坐标
        
        // 遍历所有预测框
        for i in 0..<8400 {  // 根据你的模型调整
            var maxClassScore: Float = 0
            var maxClassIndex = 0
            
            // 找出最高置信度的类别
            for j in 0..<numClasses {
                let score = Float(truncating: multiArray[[0, 4 + j, i] as [NSNumber]])
                if score > maxClassScore {
                    maxClassScore = score
                    maxClassIndex = j
                }
            }
            
            // 如果置信度超过阈值
            if maxClassScore > 0.25 {  // 根据需要调整阈值
                // 获取边界框坐标
                let x = Float(truncating: multiArray[[0, 0, i] as [NSNumber]])
                let y = Float(truncating: multiArray[[0, 1, i] as [NSNumber]])
                let w = Float(truncating: multiArray[[0, 2, i] as [NSNumber]])
                let h = Float(truncating: multiArray[[0, 3, i] as [NSNumber]])
                
                // 转换为归一化坐标
                let boundingBox = CGRect(x: CGFloat(x - w/2),
                                       y: CGFloat(y - h/2),
                                       width: CGFloat(w),
                                       height: CGFloat(h))
                
                detections.append(Detection(boundingBox: boundingBox,
                                         confidence: maxClassScore,
                                         classLabel: getClassLabel(maxClassIndex)))
            }
        }
        
        print("detected \(detections.count) objects")
//        print(detections[0])
        return detections
    }

    func getClassLabel(_ index: Int) -> String {
        // COCO 数据集的类别标签，根据你的模型调整
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

    func updateLayerGeometry() {
        let bounds = self.rootLayer.bounds
        var scaleX: CGFloat
        var scaleY: CGFloat

        // Calculate scale factors to fit the detection overlay within the preview layer
        if let previewLayerConnection = self.previewLayer.connection {
            switch previewLayerConnection.videoOrientation {
            case .portrait, .portraitUpsideDown:
                scaleX = bounds.size.width / self.bufferSize.height
                scaleY = bounds.size.height / self.bufferSize.width
            default:
                scaleX = bounds.size.width / self.bufferSize.width
                scaleY = bounds.size.height / self.bufferSize.height
            }

            // Apply transformations
            let scale = max(scaleX, scaleY)
            self.detectionOverlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: -scale))
            self.detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
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
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()

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
