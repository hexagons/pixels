//
//  RecPIX.swift
//  Pixels
//
//  Created by Hexagons on 2017-12-15.
//  Copyright © 2018 Hexagons. All rights reserved.
//

import UIKit
import AVKit

public class RecPIX: PIXOutput, PIXofaKind {//}, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    let kind: PIX.Kind = .rec
    
    var recording: Bool
    var frameIndex: Int
    var lastFrameDate: Date?
    var writer: AVAssetWriter?
    var writerVideoInput: AVAssetWriterInput?
//    var writerAudioInput: AVAssetWriterInput?
    var writerAdoptor: AVAssetWriterInputPixelBufferAdaptor?
    var currentImage: CGImage?
    var exportUrl: URL?

    public var fps: Int = 30
    public var realtime: Bool = true
    var expectsRealtime = true
    enum CodingKeys: String, CodingKey {
        case fps; case realtime
    }
    
    var customName: String?
    
    override public init() {
        
        recording = false
        realtime = true
        fps = 30
        frameIndex = 0
        lastFrameDate = nil
        writer = nil
        writerVideoInput = nil
        writerAdoptor = nil
        currentImage = nil
        exportUrl = nil
        
        super.init()

        realtimeListen()
        
    }
    
    // MARK: JSON
    
    required convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fps = try container.decode(Int.self, forKey: .fps)
        realtime = try container.decode(Bool.self, forKey: .realtime)
        setNeedsRender()
    }
    
    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fps, forKey: .fps)
        try container.encode(realtime, forKey: .realtime)
    }
    
    // MARK: Record
    
    public func startRec(name: String? = nil) throws {
        customName = name
        try startRecord()
    }
    
    public func stopRec(_ exported: @escaping (URL) -> ()) {
        guard recording else { return }
        stopRecord(done: {
            guard let url = self.exportUrl else { return }
            exported(url)
        })
    }
    
//    public func export() -> URL {
//
//    }
    
    // MARK: Export
    
    func realtimeListen() {
        pixels.listenToFrames(callback: { () -> (Bool) in
            self.frameLoop()
            return false
        })
    }
    
    func frameLoop() {
        if recording && realtime && connectedIn {
            if lastFrameDate == nil || -lastFrameDate!.timeIntervalSinceNow >= 1.0 / Double(fps) {
                if let texture = inPix?.texture {
                    recordFrame(texture: texture)
                }
            }
        }
    }
    
    override public func didRender(texture: MTLTexture, force: Bool) {
        if recording && !realtime {
            recordFrame(texture: texture)
        }
        super.didRender(texture: texture)
    }
    
    enum RecordError: Error {
        case noInPix
        case noRes
//        case stopFailed
    }
    
    func startRecord() throws {
        
        guard connectedIn else {
            throw RecordError.noInPix
        }
        guard let res = resolution else {
            throw RecordError.noRes
        }
        
        try setup(res: res)
    
        frameIndex = 0
        recording = true
        
    }
    
    func setup(res: Res) throws {
        
        let id = UUID()
        
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd HHmss"
        let dateStr = dateFormatter.string(from: date)
        
        let documents_url = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        let pixels_url = documents_url.appendingPathComponent("pixels")
        let renders_url = pixels_url.appendingPathComponent("renders")
        let id_url = renders_url.appendingPathComponent(id.uuidString)
        do {
            try FileManager.default.createDirectory(at: id_url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            pixels.log(pix: self, .error, nil, "Creating exports folder.", e: error)
            return
        }
        
        let name = customName ?? "Pixels Export \(dateStr)"
        exportUrl = id_url.appendingPathComponent("\(name).mov") // CHECK CLEAN
        
        do {

            writer = try AVAssetWriter(outputURL: exportUrl!, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecH264,
                AVVideoWidthKey: res.w,
                AVVideoHeightKey: res.h
            ]
            writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerVideoInput?.expectsMediaDataInRealTime = expectsRealtime
            writer!.add(writerVideoInput!)

//            let audioSettings: [String: Any] = [
//                AVFormatIDKey: Int(kAudioFormatMPEG4AAC) as AnyObject,
//                AVNumberOfChannelsKey: 2 as AnyObject,
//                AVSampleRateKey: 44_100 as AnyObject,
//                AVEncoderBitRateKey: 128_000 as AnyObject
//            ]
//            writerAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
//            writerAudioInput?.expectsMediaDataInRealTime = expectsRealtime
//            writer!.add(writerAudioInput!)

            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixels.colorBits.osARGB),
                kCVPixelBufferWidthKey as String: res.w,
                kCVPixelBufferHeightKey as String: res.h
            ]
            writerAdoptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerVideoInput!, sourcePixelBufferAttributes: sourceBufferAttributes)

//            let x = AVAssetWriterInputMetadataAdaptor


            writer!.startWriting()
            writer!.startSession(atSourceTime: .zero)
            
            let media_queue = DispatchQueue(label: "mediaInputQueue")
            
            writerVideoInput!.requestMediaDataWhenReady(on: media_queue, using: {
                
                if self.currentImage != nil {
                    
                    if self.writerVideoInput!.isReadyForMoreMediaData { // && self.recording
                        
                        let presentation_time = CMTime(value: Int64(self.frameIndex), timescale: Int32(self.fps))
                        
                        if !self.appendPixelBufferForImageAtURL(self.writerAdoptor!, presentation_time: presentation_time, cg_image: self.currentImage!) {
                            self.pixels.log(pix: self, .error, nil, "Export Frame. Status: \(self.writer!.status.rawValue).", e: self.writer!.error)
                        }
                        
                        self.lastFrameDate = Date()
                        self.frameIndex += 1
                        
                    } else {
                        self.pixels.log(pix: self, .error, nil, "isReadyForMoreMediaData is false.")
                    }
                    
                    self.currentImage = nil
                    
                }
                
            })
            
        } catch {
            self.pixels.log(pix: self, .error, nil, "Creating new asset writer.", e: error)
        }
        
    }
    
    func recordFrame(texture: MTLTexture) {
        
        if writer != nil && writerVideoInput != nil && writerAdoptor != nil {
        
            let ci_image = CIImage(mtlTexture: texture, options: nil)
            if ci_image != nil {
                EAGLContext.setCurrent(nil) // CHECK TESTING
                let context = CIContext.init(options: nil)
                let cg_image = context.createCGImage(ci_image!, from: ci_image!.extent)
                if cg_image != nil {
                    
                    currentImage = cg_image!
                
                } else {
                    self.pixels.log(pix: self, .error, nil, "cg_image is nil.")
                }
            } else {
                self.pixels.log(pix: self, .error, nil, "ci_image is nil.")
            }
            
        } else {
            self.pixels.log(pix: self, .error, nil, "Some writer is nil.")
        }
        
    }
    
    func stopRecord(done: @escaping () -> ()) {
        
        if writer != nil && writerVideoInput != nil && writerAdoptor != nil {
            
            writerVideoInput!.markAsFinished()
            writer!.finishWriting {
                if self.writer!.error == nil {
                    DispatchQueue.main.async {
                        done()
                    }
                } else {
                    self.pixels.log(pix: self, .error, nil, "Convering images to video failed. Status: \(self.writer!.status.rawValue).", e: self.writer!.error)
                }
            }
            
            
        } else {
//            throw RecordError.stopFailed
            pixels.log(pix: self, .error, nil, "Some writer is nil.")
        }

        frameIndex = 0
        recording = false
        
    }
    
    func appendPixelBufferForImageAtURL(_ pixel_buffer_adoptor: AVAssetWriterInputPixelBufferAdaptor, presentation_time: CMTime, cg_image: CGImage) -> Bool {
        
        var append_succeeded = false
        
        autoreleasepool {
            
            if let pixel_buffer_pool = pixel_buffer_adoptor.pixelBufferPool {
                
                let pixel_buffer_pointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
                
                let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault,
                    pixel_buffer_pool,
                    pixel_buffer_pointer
                )
                
                if let pixel_buffer = pixel_buffer_pointer.pointee, status == 0 {
                    
                    fillPixelBufferFromImage(pixel_buffer, cg_image: cg_image)
                    append_succeeded = pixel_buffer_adoptor.append(pixel_buffer, withPresentationTime: presentation_time)
                    pixel_buffer_pointer.deinitialize()
                    
                } else {
                    self.pixels.log(pix: self, .error, nil, "Allocating pixel buffer from pool.")
                }
                
                pixel_buffer_pointer.deallocate(capacity: 1)
                
            } else {
                self.pixels.log(pix: self, .error, nil, "pixel_buffer_adoptor.pixelBufferPool is nil")
            }
            
        }
        
        return append_succeeded
        
    }
    
    func fillPixelBufferFromImage(_ pixel_buffer: CVPixelBuffer, cg_image: CGImage) {
        
        CVPixelBufferLockBaseAddress(pixel_buffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        let pixel_data = CVPixelBufferGetBaseAddress(pixel_buffer)
        let rgb_color_space = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixel_data,
            width: Int(cg_image.width),
            height: Int(cg_image.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixel_buffer),
            space: rgb_color_space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        
        guard let c = context else {
            Pixels.main.log(.error, nil, "Record context failed.")
            return
        }
        
        let draw_cg_rect = CGRect(x: 0, y: 0, width: cg_image.width, height: cg_image.height)
        c.draw(cg_image, in: draw_cg_rect)
        
        CVPixelBufferUnlockBaseAddress(pixel_buffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
    }
    
    // MARK: Audio Capture
    
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        //        self.write(image: UIImage(named: "STANDARD")!, toBuffer: sampleBuffer)
//        let isVideo:Bool = output == movieOutput
//        self.videoWriter.write(sample: sampleBuffer, isVideo: isVideo)
//    }
    
}
