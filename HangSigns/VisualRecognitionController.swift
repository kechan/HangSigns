//
//  HandSignsController.swift
//  HangSigns
//
//  Created by Kelvin C on 10/28/18.
//  Copyright © 2018 Kelvin Chan. All rights reserved.
//

import UIKit
import AVFoundation
import Vision
import VideoToolbox
import Accelerate


class VisualRecognitionController: NSObject {
    var quality = AVCaptureSession.Preset.photo
    //    var quality = AVCaptureSession.Preset.hd4K3840x2160
    
    // AVFoundation stuff
    private var captureSession: AVCaptureSession?
    private var rearCamera: AVCaptureDevice?
    private var rearCameraInput: AVCaptureDeviceInput?
    
    private var photoOutput: AVCapturePhotoOutput?
    
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var flashMode = AVCaptureDevice.FlashMode.off
    
    private var photoCaptureCompletionHandler: ((UIImage?, UIImage?, Error?) -> Void)?

    var photoCaptureMode: PhotoCaptureMode = .fullscreen   // not needed for now
    
    // Vision Stuff
    private let coreMLModel = HandSign()
    private var requests = [VNRequest]()
    private var previousClassifications: [String: VNConfidence] = [:]
    private let predictionHandler: (String, VNConfidence) -> Void
    
    init(predictionHandler: @escaping (String, VNConfidence) -> Void) {
//        self.coreMLModel = coreMLModel
        self.predictionHandler = predictionHandler
    }
}

// MARK: - Main Implementations

extension VisualRecognitionController {   // Main Implementations
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        // create capture session
        func createCaptureSession() {
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = quality
        }
        
        // configure capture device
        func configureCaptureDevices() throws {
            let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
            
            let cameras = session.devices.compactMap { $0 }
            
            rearCamera = cameras.first
            
            try rearCamera?.lockForConfiguration()
            rearCamera?.focusMode = .continuousAutoFocus
            rearCamera?.unlockForConfiguration()
        }
        
        // configure capture device input
        func configureCaptureDeviceInputs() throws {
            guard let captureSession = captureSession else { throw VisualRecognitionControllerError.captureSessionIsMissing}
            
            if let rearCamera = rearCamera {
                rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                
                if captureSession.canAddInput(rearCameraInput!) {
                    captureSession.addInput(rearCameraInput!)
                }
            }
            else {
                throw VisualRecognitionControllerError.noCamerasAvailable
            }
        }
        
        // configure capture device output
        func configurePhotoOutput() throws {
            guard let captureSession = captureSession else {
                throw VisualRecognitionControllerError.captureSessionIsMissing
            }
            
            photoOutput = AVCapturePhotoOutput()
            photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])], completionHandler: nil)
            photoOutput?.isHighResolutionCaptureEnabled = true
            
            if captureSession.canAddOutput(photoOutput!) {
                captureSession.addOutput(photoOutput!)
            }
        }
        
        func configureVideoOutput() throws {
            guard let captureSession = captureSession else {
                throw VisualRecognitionControllerError.captureSessionIsMissing
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            else
            {
                throw VisualRecognitionControllerError.outputsAreInvalid
            }
            
            guard let connection = videoOutput.connection(with: .video) else {
                return
            }
            connection.isEnabled = true
            
            guard connection.isVideoOrientationSupported else { return }
            guard connection.isVideoMirroringSupported else { return }
            connection.videoOrientation = .portrait
            connection.isVideoMirrored = false
            connection.preferredVideoStabilizationMode = .auto
        }
        
        func startRunningCaptureSession() throws {
            guard let captureSession = captureSession else { throw VisualRecognitionControllerError.captureSessionIsMissing }
            
            captureSession.startRunning()
        }
        
        setupVision()
        
        DispatchQueue(label: "prepare").async {
            do {
            createCaptureSession()
            try configureCaptureDevices()
            try configureCaptureDeviceInputs()
            try configurePhotoOutput()
            try configureVideoOutput()
            try startRunningCaptureSession()
            }
            catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
        
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw VisualRecognitionControllerError.captureSessionIsMissing}
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        previewLayer?.frame = view.frame
    }
    
    func captureImage(completionHandler: @escaping (UIImage?, UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession, captureSession.isRunning else {
            completionHandler(nil, nil, VisualRecognitionControllerError.captureSessionIsMissing); return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        
        let pbpf = settings.availablePreviewPhotoPixelFormatTypes[0]
        let len = 128
        settings.previewPhotoFormat = [
            kCVPixelBufferPixelFormatTypeKey as String : pbpf,
            kCVPixelBufferWidthKey as String: len,
            kCVPixelBufferHeightKey as String: len
        ]
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionHandler = completionHandler
    }
    
}

// MARK: - Capture Photo Delegate
extension VisualRecognitionController: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            self.photoCaptureCompletionHandler?(nil, nil, error)
        }
        else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) { // TODO: Review fix for side way rotated image.
            
            let preview = UIImage(pixelBuffer: photo.previewPixelBuffer!)
            
            switch photoCaptureMode {
            case .square:
                let sqImage = cropToBounds(image: image)
                let sqPreview = cropToBounds(image: preview!)
                self.photoCaptureCompletionHandler?(sqImage, sqPreview, nil)
                classify(stillImage: sqImage, model: coreMLModel.model)
            case .fullscreen:
                self.photoCaptureCompletionHandler?(image, preview, nil)
                classify(stillImage: image, model: coreMLModel.model)
            }
         

        }
        else {
            self.photoCaptureCompletionHandler?(nil, nil, VisualRecognitionControllerError.unknown)
        }
    }

    private func classify(stillImage: UIImage, model: MLModel) {
        guard let mlModel = try? VNCoreMLModel(for: model) else {
            fatalError("Unable to convert to Vision Core ML Model")
        }
        
        // TODO: Could you a different completionHandler in future.
        let classificationRequest = VNCoreMLRequest(model: mlModel,
                                                        completionHandler: self.handleClassifications)
        
        guard let cgImage = stillImage.cgImage else {
            fatalError("Unable to convert \(stillImage) to CGImage.")
        }
        
        let cgImageOrientation = CGImagePropertyOrientation(rawValue: UInt32(stillImage.imageOrientation.rawValue))!
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([classificationRequest])
            } catch {
                print("Error performing coin classification")
            }
        }
    }
    
    fileprivate func cropToBounds(image: UIImage) -> UIImage {
        
        let contextImage: UIImage = UIImage(cgImage: image.cgImage!)
        
        let contextSize: CGSize = contextImage.size
        
        var posX: CGFloat = 0.0
        var posY: CGFloat = 0.0
        var cgwidth: CGFloat = 0.0
        var cgheight: CGFloat = 0.0
        
        // See what size is longer and create the center off of that
        if contextSize.width > contextSize.height {
            posX = ((contextSize.width - contextSize.height) / 2)
            posY = 0
            cgwidth = contextSize.height
            cgheight = contextSize.height
        } else {
            posX = 0
            posY = ((contextSize.height - contextSize.width) / 2)
            cgwidth = contextSize.width
            cgheight = contextSize.width
        }
        
        //        let rect: CGRect = CGRectMake(posX, posY, cgwidth, cgheight)
        let rect = CGRect(x: posX, y: posY, width: cgwidth, height: cgheight)
        
        // Create bitmap image from context using the rect
        //        let imageRef: CGImage = CGImageCreateWithImageInRect(contextImage.cgImage!, rect)!
        let imageRef = contextImage.cgImage?.cropping(to: rect)
        
        // Create a new image based on the imageRef and rotate back to the original orientation
        let newImage: UIImage = UIImage(cgImage: imageRef!, scale: image.scale, orientation: image.imageOrientation)
        
        return newImage
        
    }
}

// MARK: - Capture Video Delegate
extension VisualRecognitionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var requestOptions:[VNImageOption: Any] = [:]
        
        if let cameraInstrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics: cameraInstrinsicData]
        }
        
        //        let exifOrientation = self.exifOrientationFromDeviceOrientation()
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: UInt32(self.exifOrientationFromDeviceOrientation))!, options: requestOptions)
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    // only support back camera
    var exifOrientationFromDeviceOrientation: Int32 {
        let exifOrientation: DeviceOrientation
        enum DeviceOrientation: Int32 {
            case top0ColLeft = 1
            case top0ColRight = 2
            case bottom0ColRight = 3
            case bottom0ColLeft = 4
            case left0ColTop = 5
            case right0ColTop = 6
            case right0ColBottom = 7
            case left0ColBottom = 8
        }
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            exifOrientation = .left0ColBottom
        case .landscapeLeft:
            exifOrientation = .top0ColLeft
        case .landscapeRight:
            exifOrientation = .bottom0ColRight
        default:
            exifOrientation = .right0ColTop
        }
        return exifOrientation.rawValue
    }
}

// MARK: - Vision & CoreML
extension VisualRecognitionController {
    private func setupVision() {
        guard let model = try? VNCoreMLModel(for: coreMLModel.model) else {
            fatalError("Can't load Vison ML model")   // this should never happen!
        }
        
        let classificationRequest = VNCoreMLRequest(model: model, completionHandler: handleClassifications)
        
        self.requests = [classificationRequest]
    }
    
    private func handleClassifications(for request: VNRequest, error: Error?) {
        
        let decay: Float = 0.5
        
        guard let classifications = request.results as? [VNClassificationObservation], let topClassification = classifications.first else {
            return
        }
    
        for result in classifications {
            if let previousClassifications = self.previousClassifications[result.identifier] {
                self.previousClassifications[result.identifier] = (1.0 - decay) * result.confidence + previousClassifications * decay
            } else {
                self.previousClassifications[result.identifier] = (1.0 - decay)*result.confidence
            }
        }
        
        // find the top confidence item
        var maxConfidence: Float = 0.0
        var maxIdentifier: String = ""
        for (identifier, confidence) in self.previousClassifications {
            if confidence > maxConfidence {
                maxConfidence = confidence
                maxIdentifier = identifier
            }
        }

        predictionHandler(maxIdentifier, maxConfidence)

    }
}

// MARK: - Errors

extension VisualRecognitionController {
    enum VisualRecognitionControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case outputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    public enum PhotoCaptureMode {
        case fullscreen
        case square
    }
}

// MARK: Helpers

extension UIImage {
    /**
     Creates a new UIImage from a CVPixelBuffer.
     NOTE: This only works for RGB pixel buffers, not for grayscale.
     */
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        if let cgImage = cgImage {
            self.init(cgImage: cgImage)
        } else {
            return nil
        }
    }
    
    /**
     Creates a new UIImage from a CVPixelBuffer, using Core Image.
     */
    public convenience init?(pixelBuffer: CVPixelBuffer, context: CIContext) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        if let cgImage = context.createCGImage(ciImage, from: rect) {
            self.init(cgImage: cgImage)
        } else {
            return nil
        }
    }
}
