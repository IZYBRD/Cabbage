//
//  VideoCompositor.swift
//  Cabbage
//
//  Created by Vito on 06/02/2018.
//  Copyright © 2018 Vito. All rights reserved.
//

import AVFoundation
import CoreImage

open class VideoCompositor: NSObject, AVFoundation.AVVideoCompositing  {
    
    public static var ciContext: CIContext = CIContext()
    private let renderContextQueue: DispatchQueue = DispatchQueue(label: "cabbage.videocore.rendercontextqueue")
    private let renderingQueue: DispatchQueue = DispatchQueue(label: "cabbage.videocore.renderingqueue")
    private var shouldCancelAllRequests = false
    private var renderContext: AVVideoCompositionRenderContext?
    
    public var sourcePixelBufferAttributes: [String : Any]? =
    [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
     String(kCVPixelBufferOpenGLESCompatibilityKey): true,
     String(kCVPixelBufferMetalCompatibilityKey): true]
    
    public var requiredPixelBufferAttributesForRenderContext: [String : Any] =
    [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
     String(kCVPixelBufferOpenGLESCompatibilityKey): true,
     String(kCVPixelBufferMetalCompatibilityKey): true]
    
    /// Maintain the state of render context changes.
    private var internalRenderContextDidChange = false
    
    /// Actual state of render context changes.
    private var renderContextDidChange: Bool {
        get { renderContextQueue.sync { internalRenderContextDidChange } }
        set { renderContextQueue.sync { internalRenderContextDidChange = newValue } }
    }
    
    override init() {
        super.init()
    }
    
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            renderContext = newRenderContext
        }
        renderContextDidChange = true
    }
    
    enum PixelBufferRequestError: Error {
        case newRenderedPixelBufferForRequestFailure
    }
    
    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            renderingQueue.async {
                if self.shouldCancelAllRequests {
                    request.finishCancelledRequest()
                } else {
                    guard let resultPixels = self.newRenderedPixelBufferForRequest(request) else {
                        request.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                        return
                    }
                    
                    request.finish(withComposedVideoFrame: resultPixels)
                }
            }
        }
    }
    
    public func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync {
            shouldCancelAllRequests = true
        }
        renderingQueue.async {
            self.shouldCancelAllRequests = false
        }
    }
    
    // MARK: - Private
    func newRenderedPixelBufferForRequest(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let outputPixels = renderContext?.newPixelBuffer() else { return nil }
        guard let instruction = request.videoCompositionInstruction as? VideoCompositionInstruction else {
            return nil
        }
        var image = CIImage(cvPixelBuffer: outputPixels)
        
        // Background
        let backgroundImage = CIImage(color: instruction.backgroundColor).cropped(to: image.extent)
        image = backgroundImage
        
        if let destinationImage = instruction.apply(request: request) {
            image = destinationImage.composited(over: image)
        }
        
        VideoCompositor.ciContext.render(image, to: outputPixels)
        
        return outputPixels
    }
    
}
