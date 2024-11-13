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

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ingredientsList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "IngredientCell", for: indexPath)
        let ingredient = ingredientsList[indexPath.row]
        
        // Create a background view for the cell content
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor(red: 217/255, green: 217/255, blue: 217/255, alpha: 0.25)
        backgroundView.layer.cornerRadius = 10
        
        // Create container view for content
        let containerView = UIView()
        containerView.backgroundColor = backgroundView.backgroundColor
        containerView.layer.cornerRadius = 10
        
        // Style the text label
        let label = UILabel()
        label.text = "\(ingredient.name) (Quantity: \(ingredient.quantity))"
        label.font = UIFont(name: "Jost", size: 16)
        label.textColor = .white
        
        // Add label to container view
        containerView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup label constraints within container
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -15),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        // Add container view to cell
        cell.contentView.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup container constraints with horizontal insets
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
            containerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 5),
            containerView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -5)
        ])
        
        // Clear default cell styling
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        
        return cell
    }
    
    // Optional: Add swipe to delete functionality
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let removedIngredient = ingredientsList[indexPath.row]
            ingredientsList.remove(at: indexPath.row)
            detectionProcessor.unmarkIngredientAsAdded(removedIngredient.name)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    
    // Add spacing between cells
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    var previewView: UIView!
    
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    var ingredientsList: [(name: String, quantity: Int)] = []
    
    lazy var ingredientsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "IngredientCell")
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()
    
    private lazy var detectionProcessor: DetectionResultProcessor = {
        let processor = DetectionResultProcessor()
        processor.delegate = self
        print("📱 Setting up DetectionResultProcessor with delegate")
        return processor
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("📱 ViewController viewDidLoad")
        
        // Create preview view first
        previewView = UIView(frame: view.bounds)
        view.addSubview(previewView)
        
        // Setup AV Capture after preview view is added
        setupAVCapture()
        
        // Setup table view after preview view
        setupIngredientsTableView()
        
        // Verify delegate is set
        print("📱 Delegate properly set: \(detectionProcessor.delegate != nil)")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupAVCapture() {
        // print("ViewController - setupAVCapture started")
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device, make an input
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        // print("ViewController - Video device found: \(String(describing: videoDevice?.localizedName))")
        
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
            // print("ViewController - Device input created successfully")
        } catch {
            // print("Could not create video device input: \(error)")
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // Model image size is smaller.
        
        // Add a video input
        guard session.canAddInput(deviceInput) else {
            // print("ViewController - Could not add video device input to the session")
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
            // print("ViewController - Could not add video data output to the session")
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
        // print("ViewController - Preview layer setup complete")
    }
    
    func startCaptureSession() {
        // print("ViewController - Starting capture session on background thread")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            // print("ViewController - Capture session started")
        }
    }
    
    // Clean up capture setup
    func teardownAVCapture() {
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Make sure you're using the detectionProcessor here
        print("📱 Processing frame with detectionProcessor")
        // Your detection processing code here
        // Make sure you're using self.detectionProcessor, not creating a new instance
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
    
    private func setupIngredientsTableView() {
        // First add the table view to the view hierarchy
        view.addSubview(ingredientsTableView)
        
        // Style the table view
        ingredientsTableView.backgroundColor = UIColor(red: 54/255, green: 94/255, blue: 50/255, alpha: 0.93)
        ingredientsTableView.separatorStyle = .none
        ingredientsTableView.isScrollEnabled = false
        ingredientsTableView.alwaysBounceVertical = false
        ingredientsTableView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        
        // Then set up constraints
        NSLayoutConstraint.activate([
            ingredientsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ingredientsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ingredientsTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ingredientsTableView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
}
extension ViewController: DetectionResultProcessorDelegate {
    func showAddIngredientAlert(for foodItem: String) {
        print("📱 showAddIngredientAlert called for \(foodItem)")
        DispatchQueue.main.async {
            print("📱 Creating alert for \(foodItem)")
            let alert = UIAlertController(
                title: "Add Ingredient",
                message: "How many \(foodItem)(s) would you like to add?",
                preferredStyle: .alert
            )
            
            alert.addTextField { textField in
                textField.keyboardType = .numberPad
                textField.placeholder = "Enter quantity"
            }
            
            alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
                guard let self = self,
                      let quantityText = alert.textFields?.first?.text,
                      let quantity = Int(quantityText), quantity > 0 else {
                    self?.showErrorAlert(message: "Please enter a valid quantity")
                    return
                }
                
                print("📱 Adding ingredient: \(foodItem) with quantity: \(quantity)")
                self.addIngredient(name: foodItem, quantity: quantity)
                self.detectionProcessor.markIngredientAsAdded(foodItem)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            print("📱 Presenting alert")
            self.present(alert, animated: true) {
                print("📱 Alert presented successfully")
            }
        }
    }
    
    private func addIngredient(name: String, quantity: Int) {
        ingredientsList.append((name: name, quantity: quantity))
        ingredientsTableView.reloadData()
    }
}
extension ViewController {
    private func showErrorAlert(message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Error",
                message: message,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            print("📱 Showing error alert: \(message)")
            self.present(alert, animated: true) {
                print("📱 Error alert presented successfully")
            }
        }
    }
}

