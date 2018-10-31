//
//  HandSignsUIViewController.swift
//  HangSigns
//
//  Created by Kelvin C on 10/28/18.
//  Copyright © 2018 Kelvin Chan. All rights reserved.
//

import UIKit
import AVFoundation

class HandSignsUIViewController: UIViewController {
    
    @IBOutlet weak var capturePreviewView: UIView!
    
    @IBOutlet weak var photoCaptureButton: UIButton! {
        didSet {
            photoCaptureButton.layer.borderColor = UIColor.yellow.cgColor
            photoCaptureButton.layer.borderWidth = 2
            photoCaptureButton.layer.backgroundColor = UIColor.yellow.cgColor
            
            photoCaptureButton.layer.cornerRadius = min(photoCaptureButton.frame.width, photoCaptureButton.frame.height) / 2
        }
    }
    
    @IBOutlet weak var predictionLabel: UILabel!
    
    @IBOutlet weak var confidenceBar: UIProgressView!
    
    var handSignsController: VisualRecognitionController?
    let synthesizer = AVSpeechSynthesizer()
    var lastSpokenWord: String?
    let speakConfidenceThreshold: Float = 0.7
    
    override var prefersStatusBarHidden: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
//        drawGuideLines()
        
        handSignsController = VisualRecognitionController() { [unowned self] (identifier, confidence) in
            DispatchQueue.main.async {
                
                // display the top predicted class
                self.predictionLabel.text = identifier
                if confidence > self.speakConfidenceThreshold {
                    self.predictionLabel.alpha = 1.0
                } else {
                    self.predictionLabel.alpha = 0.5
                }
                
                // display confidence as a progress bar
                self.confidenceBar.progress = confidence
                if confidence > self.speakConfidenceThreshold {
                    self.confidenceBar.tintColor = UIColor.green
                } else {
                    self.confidenceBar.tintColor = UIColor.yellow
                }
                
                // Speak the word only if the confidence is high than a threshold
                if confidence > self.speakConfidenceThreshold {
                    self.speak(prediction: identifier)
                }
            }
        }

        handSignsController?.prepare { [weak self] error in
            if let error = error {
                print(error)
            }
            
            try? self?.handSignsController?.displayPreview(on: self!.capturePreviewView)
        }
        
        handSignsController?.photoCaptureMode = .square
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

// MARK: - Photo
extension HandSignsUIViewController {
    @IBAction func captureImage(_ sender: UIButton) {
        handSignsController?.captureImage{ [weak self] (image, preview, error) in
            guard let _ = image, let _ = preview else {
                print(error ?? "Image capture error")
                return
            }
        }
    }
}

// MARK: - Configure UI
extension HandSignsUIViewController {

    private func drawGuideLines() {
        let midX = self.view.bounds.midX
        let midY = self.view.bounds.midY
        
        let side = min(midX, midY) * 2.0
        
        //        let circlePath = UIBezierPath(arcCenter: CGPoint(x: midX,y: midY), radius: CGFloat(20), startAngle: CGFloat(0), endAngle:CGFloat.pi*2.0, clockwise: true)
        
        let squarePath = UIBezierPath(roundedRect: CGRect(x: midX - 0.5*side, y: midY - 0.5*side, width: side, height: side), cornerRadius: 1.0)
        
        let shapeLayerPath = CAShapeLayer()
        
        shapeLayerPath.path = squarePath.cgPath
        shapeLayerPath.fillColor = UIColor.clear.cgColor
        shapeLayerPath.strokeColor = UIColor.red.cgColor
        shapeLayerPath.lineDashPattern = [6, 2]
        shapeLayerPath.lineWidth = 2.0
        
        self.view.layer.addSublayer(shapeLayerPath)
        
        //        print("Shape layer drawn")
    }

}

// MARK: - CNN Predictions
extension HandSignsUIViewController {
    private func speak(prediction: String) {
        if (self.lastSpokenWord ?? "") != prediction {
            if self.speak(words: prediction) {
                self.lastSpokenWord = prediction
            }
        }
    }
    
    private func speak(words: String) -> Bool {
        if synthesizer.isSpeaking {
            return false
        }
        
        let utterance = AVSpeechUtterance(string: words)
        //        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        //        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-compact")
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Daniel-compact")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        synthesizer.speak(utterance)
        return true
    }
}
