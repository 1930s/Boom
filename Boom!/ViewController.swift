//
//  ViewController.swift
//  Boom!
//
//  Created by 지영 전 on 5/2/18.
//  Copyright © 2018 지영 전. All rights reserved.
//

import UIKit
import ReplayKit
import AVFoundation
import Vision
import Speech
import Photos
import SwiftGifOrigin



class ViewController: UIViewController, SFSpeechRecognizerDelegate, RPPreviewViewControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate{
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boomButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var filteredImage: UIImageView!
    @IBOutlet weak var faceGuide: UIImageView!
    @IBOutlet weak var retryButton: UIButton!
    @IBOutlet weak var capturedImage: UIImageView!
    
    @IBOutlet weak var faceguideLabel: UITextView!
    
    let screenRecorder = RPScreenRecorder.shared()
    private var isRecording = false
    var isBoomButtonOn = false
    
    //speech recognizer setup
    let speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-US"))
    
    var regRequest: SFSpeechAudioBufferRecognitionRequest?
    var regTask: SFSpeechRecognitionTask?
    let avEngine = AVAudioEngine()
    
    // Real time camera capture session
    var captureSession = AVCaptureSession()
    var previewLayer = AVCaptureVideoPreviewLayer()
    var movieOutput = AVCaptureMovieFileOutput()
    var videoCaptureDevice: AVCaptureDevice?
    
    //References to camera devices
    var backCamera: AVCaptureDevice?
    var frontCamera: AVCaptureDevice?
    var currentCamera: AVCaptureDevice?
    
    //Context for using Core Image filters
    let context = CIContext()
    
    //Track device orientation changes
    var orientation: AVCaptureVideoOrientation = .portrait
    
    //Markers for tracking facial parts
    let bubbleMarker = UIImageView (image: UIImage(named: "lightspeechbubble.png"))
    let lipMarker = UIImageView (image: UIImage(named: "particle5.gif"))
    
    
    @IBOutlet weak var txtSpeech: UITextView!
    
    //Vision framework objects
    let faceDetection = VNDetectFaceRectanglesRequest()
    let faceLandmarks = VNDetectFaceLandmarksRequest()
    let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
    let faceDetectionRequest = VNSequenceRequestHandler()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        bubbleMarker.frame = CGRect (x:0, y:0, width: 340, height: 320)
        txtSpeech.frame = CGRect (x:0, y:0, width: 250, height: 120)
        lipMarker.frame = CGRect(x:0, y:0, width:200, height:1200)
        lipMarker.image = UIImage.gif(name: "particle5")
        bubbleMarker.isHidden = true
        txtSpeech.isHidden = true
        lipMarker.isHidden = true
        self.view.addSubview(bubbleMarker)
        self.view.addSubview(txtSpeech)
        self.view.addSubview(lipMarker)

        boomButton.isEnabled = false
        cameraButton.layer.cornerRadius = cameraButton.frame.size.height/3
        cameraButton.layer.masksToBounds = true
        txtSpeech.text = ""
        
        speechRecognizer?.delegate = self
        getPermissionSpeechRecognizer()
        
        // camera device setup
        setupDevice()
        setupInputOutput()
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        //Detect device orientation changes
        orientation = AVCaptureVideoOrientation(rawValue:
            UIApplication.shared.statusBarOrientation.rawValue)!
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func getPermissionSpeechRecognizer() {
        SFSpeechRecognizer.requestAuthorization { (status) in
            switch status {
            case .authorized:
                self.boomButton.isEnabled = true
                break
            case .denied:
                self.boomButton.isEnabled = false
                break
            case .notDetermined:
                self.boomButton.isEnabled = false
                break
            case .restricted:
                self.boomButton.isEnabled = false
                break
            }
        }
    }
    
    func startRecording() {
        
        //Cancel task if already running
        if regTask != nil {
            regTask?.cancel()
            regTask = nil
        }
        
        
        //Create and AVAudioSession for audio recording
        let avAudioSession = AVAudioSession.sharedInstance()
        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryRecord)
            try avAudioSession.setMode(AVAudioSessionModeMeasurement)
            try avAudioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session is not active")
        }
        
        //Check the Audio input.
        let inputEngineNode = avEngine.inputNode
        
        regRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = regRequest else {
            fatalError("SFSpeechAudioBufferRecognitionRequest object is not created")
        }
        recognitionRequest.shouldReportPartialResults = true
        
        //Start task of speech recognition
        regTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in
            
            var isComplete = false
            
            if result != nil {
                self.txtSpeech.text = result?.bestTranscription.formattedString
                isComplete = (result?.isFinal)!
                self.lipMarker.isHidden = false
            }
            
            
            if error != nil || isComplete {
                self.avEngine.stop()
                inputEngineNode.removeTap(onBus: 0)
                
                self.regRequest = nil
                self.regTask = nil
                self.lipMarker.isHidden = true
            }
        })
        
        
        //Set Formation of Audio Input
        let recordingFormat = inputEngineNode.outputFormat(forBus: 0)
        inputEngineNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.regRequest?.append(buffer)
        }
        
        avEngine.prepare()
        
        do {
            try avEngine.start()
        } catch {
            print("some error")
        }
    }
    
    //MARK:- SFSpeechRecognizer Delegate
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        
    }
    
    func speechButtonTapped(){
    if avEngine.isRunning {
    avEngine.stop()
    regRequest?.endAudio()
    txtSpeech.text = ""
    
    } else {
    startRecording()

    }
    
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        // Set correct device orientation.
        connection.videoOrientation = orientation
        
        // Get pixel buffer.
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        var cameraImage = CIImage(cvImageBuffer: pixelBuffer!)
        
        // Mirror camera image if using front camera.
        if currentCamera == frontCamera {
            cameraImage = cameraImage.oriented(.upMirrored)
        }
        
        var filteredImage: UIImage!
         filteredImage =  UIImage(ciImage: cameraImage)
        
        
        self.detectFace(on: cameraImage.oriented(.upMirrored))
        
        // Set image view outlet with filtered image.
        DispatchQueue.main.async {
            self.filteredImage.image = filteredImage
        }
    }
    
    func viewReset() {
        statusLabel.text = "Ready to Record"
        statusLabel.textColor = UIColor.black
    }
    
    func recordButtonTapped(){
        if !isRecording {
            startScreenRecording()
        }
        else {
            stopScreenRecording()
        }
    }
    
    func startScreenRecording() {
        print("plz record")
        
        guard screenRecorder.isAvailable else {
            print("Recording is not available at this time.")
            return
        }
        
        screenRecorder.isMicrophoneEnabled = true
        screenRecorder.startRecording{ [unowned self] (error) in
            
            guard error == nil else {
                print("There was an error starting the recording.")
                return
            }
            
            print("Started Recording Successfully")
            self.statusLabel.text = "Recording..."
            self.statusLabel.textColor = UIColor.red
            self.isRecording = true
            
        }
        
    }
    
    func stopScreenRecording() {
        
        print("Why")
        screenRecorder.stopRecording { [unowned self] (preview, error) in
            print("Stopped recording")
            
            guard preview != nil else {
                print("Preview controller is not available.")
                return
            }
            
            let alert = UIAlertController(title: "Recording Finished", message: "Would you like to edit or delete your recording?", preferredStyle: .alert)
            
            let deleteAction = UIAlertAction(title: "Delete", style: .destructive, handler: { (action: UIAlertAction) in
                self.screenRecorder.discardRecording(handler: { () -> Void in
                    print("Recording suffessfully deleted.")
                })
            })
            
            let editAction = UIAlertAction(title: "Edit", style: .default, handler: { (action: UIAlertAction) -> Void in
                preview?.previewControllerDelegate = self
                self.present(preview!, animated: true, completion: nil)
            })
            
            alert.addAction(editAction)
            alert.addAction(deleteAction)
            self.present(alert, animated: true, completion: nil)
            
            self.isRecording = false
            
            self.viewReset()
 
        }
        
    }
    
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
    }
    
    
    @IBAction func boomButtonTapped(_ sender: Any) {
        isBoomButtonOn = !isBoomButtonOn
        recordButtonTapped()
        speechButtonTapped()
        
        bubbleMarker.isHidden = !isBoomButtonOn
        txtSpeech.isHidden = !isBoomButtonOn
        faceGuide.isHidden = isBoomButtonOn
        faceguideLabel.isHidden = isBoomButtonOn
        let bubbleImage = isBoomButtonOn ? UIImage(named: "icon_BoomAfter.png"): UIImage(named: "icon_BoomBefore.png")
        boomButton.setImage(bubbleImage, for: .normal)
    }

    @IBAction func retryButtonTapped(_ sender: Any) {
        recordButtonTapped()
        speechButtonTapped()
        
    }
    
    

    
    
}

// Helper methods for vision framekwork.
extension ViewController {
    
    func detectFace(on image: CIImage) {
        try? faceDetectionRequest.perform([faceDetection], on: image)
        if let results = faceDetection.results as? [VNFaceObservation] {
            if !results.isEmpty {
                faceLandmarks.inputFaceObservations = results
                detectLandmarks(on: image)
                DispatchQueue.main.async {
                }
            }
        }
    }
    
    func detectLandmarks(on image: CIImage) {
        try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: image)
        if let landmarksResults = faceLandmarks.results as? [VNFaceObservation] {
            for observation in landmarksResults {
                DispatchQueue.main.async {
                    if let boundingBox = self.faceLandmarks.inputFaceObservations?.first?.boundingBox {
                        let faceBoundingBox = boundingBox.scaled(to: self.view.bounds.size)
                        
           
                        let nose = observation.landmarks?.nose
                        let lips = observation.landmarks?.innerLips
                        
                        
                        self.centerMarkerForFace(nose, faceBoundingBox, self.bubbleMarker, _totalX: 600.0, _totalY: 2400.0)
                        self.centerMarkerForFace(nose, faceBoundingBox, self.txtSpeech, _totalX: 600.0, _totalY: 2400.0)
                        self.faceGuide.frame = CGRect(x:0, y:0, width:faceBoundingBox.width*3, height:faceBoundingBox.height*2.5)
                        self.centerMarkerForFace(nose, faceBoundingBox, self.faceGuide, _totalX: 0.0, _totalY: 0.0)
                        self.lipMarker.frame = CGRect(x:0, y:0, width:faceBoundingBox.width, height:faceBoundingBox.height*6)
                        self.centerMarkerForFace(lips, faceBoundingBox, self.lipMarker,_totalX: 0.0 ,_totalY: 0.0)
                        
                    }
                }
            }
        }
    }
    
    func centerMarkerForFace(_ landmark: VNFaceLandmarkRegion2D?, _ boundingBox: CGRect, _ markerView: UIView, _totalX: CGFloat, _totalY: CGFloat) {
        if let points = landmark?.normalizedPoints {
            // Caculate the avg point from normalized points.
            var totalXX: CGFloat = _totalX
            var totalYY: CGFloat = _totalY
            for point in points {
                totalXX += point.x * boundingBox.width + boundingBox.origin.x
                totalYY += point.y * boundingBox.height + boundingBox.origin.y
            }
            let avgX = totalXX / CGFloat(points.count)
            let avgY = totalYY / CGFloat(points.count)
            
            // Position marker view.
            markerView.center = CGPoint(x: self.view.bounds.width - avgX , y: self.view.bounds.height - avgY)
        }
    }

}

extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        return CGRect(
            x: self.origin.x * size.width,
            y: self.origin.y * size.height,
            width: self.size.width * size.width,
            height: self.size.height * size.height
        )
    }
}

// Helper methods to setup camera capture view.
extension ViewController {
    
    func setupDevice() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                      mediaType: AVMediaType.video, position: AVCaptureDevice.Position.unspecified)
        let devices = deviceDiscoverySession.devices
        
        for device in devices {
            if device.position == AVCaptureDevice.Position.back {
                backCamera = device
            }
            else if device.position == AVCaptureDevice.Position.front {
                frontCamera = device
            }
        }
        
        currentCamera = backCamera
        
    }
    
    func setupInputOutput() {
        
        do {
            setupCorrectFramerate(currentCamera: currentCamera!)
            
            let captureDeviceInput = try AVCaptureDeviceInput(device: currentCamera!)
            captureSession.sessionPreset = AVCaptureSession.Preset.hd1280x720
            
            if captureSession.canAddInput(captureDeviceInput) {
                captureSession.addInput(captureDeviceInput)
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            captureSession.startRunning()
        } catch {
            print(error)
        }
    }
    
    func setupCorrectFramerate(currentCamera: AVCaptureDevice) {
        for vFormat in currentCamera.formats {
            var ranges = vFormat.videoSupportedFrameRateRanges as [AVFrameRateRange]
            let frameRates = ranges[0]
            do {
                //set to 240fps - available types are: 30, 60, 120 and 240 and custom
                // lower framerates cause major stuttering
                if frameRates.maxFrameRate == 240 {
                    try currentCamera.lockForConfiguration()
                    currentCamera.activeFormat = vFormat as AVCaptureDevice.Format
                    //for custom framerate set min max activeVideoFrameDuration to whatever you like, e.g. 1 and 180
                    currentCamera.activeVideoMinFrameDuration = frameRates.minFrameDuration
                    currentCamera.activeVideoMaxFrameDuration = frameRates.maxFrameDuration
                }
            }
            catch {
                print("Could not set active format")
                print(error)
            }
        }
    }
    
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                         mediaType: AVMediaType.video,
                                                         position: .unspecified) as AVCaptureDevice.DiscoverySession
        for device in discovery.devices as [AVCaptureDevice] {
            if device.position == position {
                return device
            }
        }
                 print ("cameraWithPosition")
        return nil
        

    }
    
    func switchCameraInput() {
        self.captureSession.beginConfiguration()
        
        var existingConnection:AVCaptureDeviceInput!
        
        for connection in self.captureSession.inputs {
            let input = connection as! AVCaptureDeviceInput
            if input.device.hasMediaType(AVMediaType.video) {
                existingConnection = input
            }
            
        }
        
        self.captureSession.removeInput(existingConnection)
        
        var newCamera:AVCaptureDevice!
        if let oldCamera = existingConnection {
            newCamera = oldCamera.device.position == .back ? frontCamera : backCamera
            currentCamera = newCamera
        }
        
        var newInput: AVCaptureDeviceInput!
        
        do {
            newInput = try AVCaptureDeviceInput(device: newCamera)
            self.captureSession.addInput(newInput)
        } catch {
            print(error)
        }
        
        self.captureSession.commitConfiguration()
    }
    
}

extension UIImage {
    class func imageWithView(_ view: UIView) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.isOpaque, 0)
        defer { UIGraphicsEndImageContext() }
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}


