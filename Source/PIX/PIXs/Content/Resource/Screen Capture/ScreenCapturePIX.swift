//
//  ScreenCapturePIX.swift
//  PixelKit
//
//  Created by Anton Heestand on 2018-07-26.
//  Open Source - MIT License
//

#if os(macOS) && !targetEnvironment(macCatalyst)

import AVKit
import RenderKit
import Resolution

final public class ScreenCapturePIX: PIXResource, PIXViewable {
        
    override public var shaderName: String { return "contentResourcePIX" }
    
    // MARK: - Private Properties
    
    var helper: ScreenCaptureHelper?
    
    // MARK: - Public Properties
    
    @LiveInt("screenIndex", range: 0...2) public var screenIndex: Int = 0 { didSet { setupScreenCapture() } }
    
    public override var liveList: [LiveWrap] {
        super.liveList + [_screenIndex]
    }
    
    // MARK: - Life Cycle
    
    public required init() {
        super.init(name: "Screen Capture", typeName: "pix-content-resource-screen-capture")
        setupScreenCapture()
    }
    
    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        setupScreenCapture()
    }
    
    deinit {
        helper?.stop()
    }
    
    public override func destroy() {
        super.destroy()
        helper?.stop()
        helper = nil
    }
    
    // MARK: Setup
    
    func setupScreenCapture() {
        helper?.stop()
        helper = ScreenCaptureHelper(screenIndex: screenIndex, setup: { [weak self] _ in
            guard let self = self else { return }
            self.pixelKit.logger.log(node: self, .info, .resource, "Screen Capture setup.")
        }, captured: { [weak self] pixelBuffer in
            guard let self = self else { return }
            self.pixelKit.logger.log(node: self, .info, .resource, "Screen Capture frame captured.", loop: true)
            let isFirstPixelBuffer: Bool = self.resourcePixelBuffer == nil
            self.resourcePixelBuffer = pixelBuffer
            if isFirstPixelBuffer || Resolution(pixelBuffer: pixelBuffer) != self.finalResolution {
                self.applyResolution { [weak self] in
                    self?.render()
                }
            } else {
                self.render()
            }
        })
    }
    
}

class ScreenCaptureHelper: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate/*, AVCapturePhotoCaptureDelegate*/ {
    
    let pixelKit = PixelKit.main
    
    var screenInput: AVCaptureScreenInput?
    
    let captureSession: AVCaptureSession
    let videoOutput: AVCaptureVideoDataOutput
//    let photoOutput: AVCapturePhotoOutput?

    var initialFrameCaptured = false
    
    let setupCallback: (CGSize) -> ()
    let capturedCallback: (CVPixelBuffer) -> ()
    
    init(screenIndex: Int, setup: @escaping (CGSize) -> (), captured: @escaping (CVPixelBuffer) -> ()) {
        
        let id = NSScreen.screens[screenIndex].deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! CGDirectDisplayID
        screenInput = AVCaptureScreenInput(displayID: id)
        
        setupCallback = setup
        capturedCallback = captured
        
        captureSession = AVCaptureSession()
        videoOutput = AVCaptureVideoDataOutput()
        
        
        super.init()
        
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelKit.render.bits.os]
        
        if screenInput != nil {
            if captureSession.canAddInput(screenInput!) {
                captureSession.addInput(screenInput!)
                if captureSession.canAddOutput(videoOutput){
                    captureSession.addOutput(videoOutput)
                    let queue = DispatchQueue(label: "se.hexagons.pixelKit.pix.screen.capture.queue")
                    videoOutput.setSampleBufferDelegate(self, queue: queue)
                    start()
                } else {
                    pixelKit.logger.log(.error, .resource, "Screen can't add output.")
                }
            } else {
                pixelKit.logger.log(.error, .resource, "Screen can't add input.")
            }
        } else {
            pixelKit.logger.log(.error, .resource, "Screen not found.")
        }
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            pixelKit.logger.log(.error, .resource, "Camera buffer conversion failed.")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !self.initialFrameCaptured {
                self.setup(pixelBuffer)
                self.initialFrameCaptured = true
            }
            
            self.capturedCallback(pixelBuffer)
            
        }
        
    }
    
    func setup(_ pixelBuffer: CVPixelBuffer) {
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let resolution = CGSize(width: width, height: height)
        
        setupCallback(resolution)
        
    }
    
    func start() {
        captureSession.startRunning()
    }
    
    func stop() {
        captureSession.stopRunning()
    }

}

#endif
