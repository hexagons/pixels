//
//  PIX.swift
//  PixelKit
//
//  Created by Anton Heestand on 2018-07-20.
//  Open Source - MIT License
//

import RenderKit
import Resolution
import RenderKit
import Resolution
import CoreGraphics
import Metal
import simd
import Combine

open class PIX: NODE, ObservableObject, Equatable {
    
    public var id = UUID()
    public var name: String
    public let typeName: String
    
    public weak var delegate: NODEDelegate?
    
    let pixelKit = PixelKit.main
    
    open var shaderName: String {
        typeName
            .replacingOccurrences(of: "pix-", with: "")
            .camelCased
            + "PIX"
    }
    
    open var overrideBits: Bits? { nil }
    
    open var liveList: [LiveWrap] { [] }
    open var values: [Floatable] { [] }
    open var extraUniforms: [CGFloat] { [] }
    open var uniforms: [CGFloat] {
        var uniforms: [CGFloat] = values.flatMap(\.floats)
        uniforms.append(contentsOf: extraUniforms)
        return uniforms
    }
    
    open var uniformArray: [[CGFloat]] { [] }
    public var uniformArrayMaxLimit: Int? { nil }
    public var uniformIndexArray: [[Int]] { [] }
    public var uniformIndexArrayMaxLimit: Int? { nil }
       
    
    @Published public var finalResolution: Resolution = PixelKit.main.fallbackResolution
    
    var customResolution: Resolution? { nil }
    
    
    open var vertexUniforms: [CGFloat] { return [] }
    public var shaderNeedsResolution: Bool { return false }
    
    public var bypass: Bool = false {
        didSet {
            guard !bypass else { return }
            render()
        }
    }

    public var _texture: MTLTexture?
    public var texture: MTLTexture? {
        get {
            guard !bypass else {
                guard let input = self as? NODEInIO else { return nil }
                return input.inputList.first?.texture
            }
            return _texture
        }
        set {
            _texture = newValue
            if newValue != nil {
                nextTextureAvalibleCallback?()
            }
        }
    }
    public var didRenderTexture: Bool {
        return _texture != nil
    }
    var nextTextureAvalibleCallback: (() -> ())?
    public func nextTextureAvalible(_ callback: @escaping () -> ()) {
        nextTextureAvalibleCallback = {
            callback()
            self.nextTextureAvalibleCallback = nil
        }
    }
    
    open var additiveVertexBlending: Bool { false }
    
    public var pixView: PIXView!
    public var view: NODEView { pixView }
    public var additionalViews: [NODEView] = []
    
    public var viewInterpolation: ViewInterpolation = .linear {
        didSet {
            view.metalView.viewInterpolation = viewInterpolation
        }
    }
    @available(*, deprecated, renamed: "interpolation")
    public var interpolate: PixelInterpolation {
        get { interpolation }
        set { interpolation = newValue }
    }
    public var interpolation: PixelInterpolation = .linear { didSet { updateSampler() } }
    public var extend: ExtendMode = .zero { didSet { updateSampler() } }
    public var mipmap: MTLSamplerMipFilter = .linear { didSet { updateSampler() } }
    var compare: MTLCompareFunction = .never
    
    public var pipeline: MTLRenderPipelineState!
    public var sampler: MTLSamplerState!
    public var allGood: Bool {
        return pipeline != nil && sampler != nil
    }
    
    public var customRenderActive: Bool = false
    public var customRenderDelegate: CustomRenderDelegate?
    public var customMergerRenderActive: Bool = false
    public var customMergerRenderDelegate: CustomMergerRenderDelegate?
    public var customGeometryActive: Bool = false
    public var customGeometryDelegate: CustomGeometryDelegate?
    open var customMetalLibrary: MTLLibrary? { return nil }
    open var customVertexShaderName: String? { return nil }
    open var customVertexTextureActive: Bool { return false }
    open var customVertexNodeIn: (NODE & NODEOut)? { return nil }
//    open var customVertexNodeIn: (NODE & NODEOut)?
    open var customMatrices: [matrix_float4x4] { return [] }
//    public var customLinkedNodes: [NODE] = []
    
    public var renderInProgress = false
//    let passthroughRender: PassthroughSubject = PassthroughSubject<RenderRequest, Never>()
    private var renderQueue: [RenderRequest] = []
//    public var needsRender = false {
//        didSet {
//            guard needsRender else { return }
//            guard pixelKit.render.engine.renderMode == .direct else { return }
//            pixelKit.render.engine.renderNODE(self, done: { _ in })
//        }
//    }
    public var renderIndex: Int = 0
    public var contentLoaded: Bool?
    var inputTextureAvalible: Bool?
    var generatorNotBypassed: Bool?
    
    static let metalLibrary: MTLLibrary = {
        do {
            return try PixelKit.main.render.metalDevice.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            fatalError("Loading Metal Library Failed: \(error.localizedDescription)")
        }
    }()
    
    public var destroyed = false
    public var cancellables: [AnyCancellable] = []
    
    // MARK: - Life Cycle
    
    init(name: String, typeName: String) {
        
        self.name = name
        self.typeName = typeName
        
        setupPIX()
    }
    
    // MARK: - Setup
    
    func setupPIX() {
        
        let pixelFormat: MTLPixelFormat = overrideBits?.pixelFormat ?? PixelKit.main.render.bits.pixelFormat
        pixView = PIXView(pix: self, with: PixelKit.main.render, pixelFormat: pixelFormat)
        
        setupShader()
            
        pixelKit.render.add(node: self)
        
        pixelKit.logger.log(node: self, .detail, nil, "Linked with PixelKit.", clean: true)
        
        for liveProp in liveList {
            liveProp.node = self
        }
        
    }
    
    func setupShader() {
        guard shaderName != "" else {
            pixelKit.logger.log(node: self, .fatal, nil, "Shader not defined.")
            return
        }
        do {
            guard let function: MTLFunction = PIX.metalLibrary.makeFunction(name: shaderName) else {
                pixelKit.logger.log(node: self, .fatal, nil, "Setup of Metal Function Failed")
                return
            }
            pipeline = try pixelKit.render.makeShaderPipeline(function, with: nil, addMode: additiveVertexBlending, overrideBits: overrideBits)
            #if !os(tvOS) || !targetEnvironment(simulator)
            sampler = try pixelKit.render.makeSampler(interpolate: interpolation.mtl, extend: extend.mtl, mipFilter: mipmap)
            #endif
        } catch {
            pixelKit.logger.log(node: self, .fatal, nil, "Setup Failed", e: error)
        }
    }
    
    // MARK: - Sampler
    
    func updateSampler() {
        do {
            #if !os(tvOS) || !targetEnvironment(simulator)
            sampler = try pixelKit.render.makeSampler(interpolate: interpolation.mtl, extend: extend.mtl, mipFilter: mipmap)
            #endif
            pixelKit.logger.log(node: self, .info, nil, "New Sample Mode. Interpolate: \(interpolation) & Extend: \(extend)")
            render()
        } catch {
            pixelKit.logger.log(node: self, .error, nil, "Error setting new Sample Mode. Interpolate: \(interpolation) & Extend: \(extend)", e: error)
        }
    }
    
    // MARK: - Render
    
    public func render() {
        PixelKit.main.render.logger.log(node: self, .detail, .render, "Render Requested", loop: true)
        let frameIndex = PixelKit.main.render.frameIndex
        let renderRequest = RenderRequest(frameIndex: frameIndex, node: self, completion: nil)
//        passthroughRender.send(renderRequest)
        queueRender(renderRequest)
    }
    
    public func render(completion: ((Result<RenderResponse, Error>) -> ())? = nil,
                       via upstreamRenderRequest: RenderRequest) {
        PixelKit.main.render.logger.log(node: self, .detail, .render, "Render Requested with Completion Handler", loop: true)
        let frameIndex = PixelKit.main.render.frameIndex
        let renderRequest = RenderRequest(frameIndex: frameIndex, node: self, completion: completion, via: upstreamRenderRequest)
//        passthroughRender.send(renderRequest)
        queueRender(renderRequest)
    }
    
//    private func registerForRender() {
//        var willRenderFromFrameIndex: Int?
////        var willRenderTimer: Timer?
//        passthroughRender
////            .removeDuplicates(by: { a, b in
////                a.frameIndex == b.frameIndex
////            })
//            .sink { renderRequest in
//                print("Combine \"\(self.name)\" [[Register for Render]] Requested at \(renderRequest.frameIndex)")
//                self.promiseRender(renderRequest)
//                if let frameIndex: Int = willRenderFromFrameIndex {
//                    if frameIndex == renderRequest.frameIndex {
//                        return
//                    } else {
//                        print("Combine \"\(self.name)\" [[Register for Render]] Direct at \(renderRequest.frameIndex) >=>=>")
//                        self.queueRender(renderRequest)
//                    }
//                }
//                willRenderFromFrameIndex = renderRequest.frameIndex
////                willRenderTimer?.invalidate()
////                willRenderTimer = Timer(timeInterval: PixelKit.main.render.maxSecondsPerFrame, repeats: false, block: { _ in
//                DispatchQueue.main.async {
//                    willRenderFromFrameIndex = nil
////                    willRenderTimer = nil
//                    print("Combine \"\(self.name)\" [[Register for Render]] Delay at \(renderRequest.frameIndex) >->->")
//                    self.queueRender(renderRequest)
//                }
////                })
////                RunLoop.current.add(willRenderTimer!, forMode: .common)
//            }
//            .store(in: &cancellables)
//    }
    
    private func promiseRender(_ renderRequest: RenderRequest) {
        if let nodeOut: NODEOut = self as? NODEOut {
            nodeOut.renderPromisePublisher.send(renderRequest)
        }
    }
    
    func promisedRender(_ renderRequest: RenderRequest) {
        promiseRender(renderRequest)
    }
    
    private func queueRender(_ renderRequest: RenderRequest) {
        
        guard !bypass else {
            #warning("Bypass should Render Outs")
            PixelKit.main.render.logger.log(node: self, .detail, .render, "Queue Render Bypassed", loop: true)
            return
        }

        guard !renderInProgress else {
            renderQueue.append(renderRequest)
            PixelKit.main.render.logger.log(node: self, .detail, .render, "Queue Render in Progress", loop: true)
            return
        }
        
//        PixelKit.main.render.logger.log(node: self, .detail, .render, "Queue Request Render", loop: true)
        
        PixelKit.main.render.queuer.add(request: renderRequest) { queueResult in
            switch queueResult {
            case .success:
    
                PixelKit.main.render.logger.log(node: self, .detail, .render, "Queue Will Render", loop: true)
                
                PixelKit.main.render.engine.renderNODE(self, renderRequest: renderRequest) { result in
                    
                    switch result {
                    case .success(let renderPack):
                        self.didRender(renderPack: renderPack)
                    case .failure(let error):
                        PixelKit.main.logger.log(node: self, .error, .render, "Render Failed", loop: true, e: error)
                    }
                    
                    renderRequest.completion?(result.map(\.response))
                    
                    if !self.renderQueue.isEmpty {
                        let firstRequestFrameIndex: Int = self.renderQueue.map(\.frameIndex).sorted().first!
                        let completions = self.renderQueue.compactMap(\.completion)
                        self.renderQueue = []
                        #warning("Merge of Many Render Requests")
                        let renderRequest = RenderRequest(frameIndex: firstRequestFrameIndex, node: self, completion: { result in
                            completions.forEach { completion in
                                completion(result)
                            }
                        })
                        self.queueRender(renderRequest)
                    }
                }
                
            case .failure(let error):
                if error as? Queuer.QueuerError != Queuer.QueuerError.duplicate {
                    PixelKit.main.render.logger.log(node: self, .warning, .render, "Queue Can't Render", loop: true, e: error)
                }
                renderRequest.completion?(.failure(error))
            }
        }
        
    }
        
//        private func sendToRender((Result<RenderedTexture, Error>) -> ())) {
//
//        }
    
//    open func setNeedsRender() {
//        setNeedsRender(first: true)
//    }
//    public func setNeedsRender(first: Bool = true) {
//        guard !bypass || self is PIXGenerator else {
//            #warning("Func renderOuts() will send self.texture even on bypass")
//            renderOuts()
//            return
//        }
////        checkSetup()
//        guard !needsRender else {
////            pixelKit.logger.log(node: self, .warning, .render, "Already requested.", loop: true)
//            return
//        }
//        guard !rendering && !inRender else {
//            pixelKit.logger.log(node: self, .debug, .render, "No need to render. Render in progress.", loop: true)
//            return
//        }
////        guard resolution != nil else {
////            pixelKit.logger.log(node: self, .warning, .render, "Resolution unknown.", loop: true)
////            return
////        }
//        guard view.metalView.resolution != nil else {
//            guard first else {
//                pixelKit.logger.log(node: self, .debug, .render, "Metal View could not be set with applyResolution.", loop: true)
//                return
//            }
//            pixelKit.logger.log(node: self, .warning, .render, "Metal View res not set.")//, loop: true)
//            pixelKit.logger.log(node: self, .debug, .render, "Auto applying Resolution...")//, loop: true)
//            applyResolution {
//                self.setNeedsRender(first: false)
//            }
//            return
//        }
//        pixelKit.logger.log(node: self, .detail, .render, "Requested.", loop: true)
////        delegate?.pixWillRender(self)
//        needsRender = true
//    }
    
//    func checkSetup() {
//        if let pixResource = self as? PIXResource {
//            if pixResource.resourcePixelBuffer != nil || pixResource.resourceTexture != nil {
//                if contentLoaded != true {
//                    let wasBad = contentLoaded == false
//                    contentLoaded = true
//                    if wasBad {
//                        setupShader()
//                    }
//                }
//            } else {
//                if contentLoaded != false {
//                    contentLoaded = false
//                    setupShader()
//                }
//                contentLoaded = false
//                pixelKit.logger.log(node: self, .warning, .render, "Content not loaded.", loop: true)
//            }
//        }
//        if let input = self as? NODEInIO, !(self is NODEMetal) {
//            let hasInTexture: Bool
//            if pixelKit.render.engine.renderMode.isTile {
//                if self is NODE3D {
//                    hasInTexture = (input.inputList.first as? NODETileable3D)?.tileTextures != nil
//                } else {
//                    hasInTexture = (input.inputList.first as? NODETileable2D)?.tileTextures != nil
//                }
//            } else {
//                hasInTexture = input.inputList.first?.texture != nil
//            }
//            if hasInTexture {
//                let wasBad = inputTextureAvalible == false
//                if inputTextureAvalible != true {
//                    inputTextureAvalible = true
//                    if wasBad {
//                        setupShader()
//                    }
//                }
//            } else {
//                if inputTextureAvalible != false {
//                    inputTextureAvalible = false
//                    setupShader()
//                }
//            }
//        }
//        if self is PIXGenerator {
//            if !bypass {
//                let wasBad = generatorNotBypassed == false
//                if generatorNotBypassed != true {
//                    generatorNotBypassed = true
//                    if wasBad {
//                        setupShader()
//                    }
//                }
//            } else {
//                if generatorNotBypassed != false {
//                    generatorNotBypassed = false
//                    setupShader()
//                }
//            }
//        }
//    }
    
    open func didRender(renderPack: RenderPack) {
        let firstRender = self.texture == nil
        self.texture = renderPack.response.texture
        renderIndex += 1
        delegate?.nodeDidRender(self)
//        if pixelKit.render.engine.renderMode != .frameTree {
//            for customLinkedPix in customLinkedNodes {
//                customLinkedPix.render()
//            }
        renderOuts(renderPack: renderPack)
        renderCustomVertexTexture()
//        }
//        if firstRender {
//            // FIXME: Temp double render fix.
//            render()
//        }
    }
        
//    public func didRenderTiles(force: Bool) {
//        didRender(force: force)
//    }
    
    func renderOuts(renderPack: RenderPack) {
        guard let texture: MTLTexture = texture else {
            PixelKit.main.logger.log(node: self, .warning, .connection, "Can't render out, texture is nil.", loop: true)
            return
        }
        if let nodeOut: NODEOut = self as? NODEOut {
            nodeOut.renderPublisher.send(renderPack)
        }
//        if let pixOut = self as? NODEOutIO {
//            for pixOutPath in pixOut.outputPathList {
////                guard let pix = pixOutPath?.pixIn else { continue }
//                let pix = pixOutPath.nodeIn
//                guard !pix.destroyed else { continue }
//                guard pix.id != self.id else {
//                    pixelKit.logger.log(node: self, .error, .render, "Connected to self.")
//                    continue
//                }
//                pix.render()
//            }
//        }
    }
    
    func renderCustomVertexTexture() {
        for pix in pixelKit.render.linkedNodes {
            if pix.customVertexTextureActive {
                if let input = pix.customVertexNodeIn {
                    if input.id == self.id {
                        pix.render()
                    }
                }
            }
        }
    }
    
    func clearRender() {
        pixelKit.logger.log(node: self, .info, .render, "Clear Render")
        removeRes()
    }
    
    // MARK: - Out Path

//    class WeakOutPath {
//        weak var outPath: OutPath?
//        init(_ outPath: OutPath) {
//            self.outPath = outPath
//        }
//    }
//    struct WeakOutPaths: Collection {
//        private var weakOutPaths: [WeakOutPath] = []
//        init(_ outPaths: [OutPath]) {
//            weakOutPaths = outPaths.map { WeakOutPath($0) }
//        }
//        var startIndex: Int { return weakOutPaths.startIndex }
//        var endIndex: Int { return weakOutPaths.endIndex }
//        subscript(_ index: Int) -> OutPath? {
//            return weakOutPaths[index].outPath
//        }
//        func index(after idx: Int) -> Int {
//            return weakOutPaths.index(after: idx)
//        }
//        mutating func append(_ outPath: OutPath) {
//            weakOutPaths.append(WeakOutPath(outPath))
//        }
//        mutating func remove(_ outPath: OutPath) {
//            for (i, weakOutPath) in weakOutPaths.enumerated() {
//                if weakOutPath.outPath != nil && weakOutPath.outPath!.pixIn == outPath.pixIn {
//                    weakOutPaths.remove(at: i)
//                    break
//                }
//            }
//        }
//        mutating func remove(at index: Int) {
//            weakOutPaths.remove(at: index)
//        }
//    }
    
    // MARK: - Connect
    
    func setNeedsConnectSingle(new newInPix: (NODE & NODEOut)?, old oldInPix: (NODE & NODEOut)?) {
        guard var pixInIO = self as? NODE & NODEInIO else { pixelKit.logger.log(node: self, .error, .connection, "NODEIn's Only"); return }
        if let oldPixOut = oldInPix {
            var pixOut = oldPixOut as! (NODE & NODEOutIO)
            for (i, pixOutPath) in pixOut.outputPathList.enumerated() {
                if pixOutPath.nodeIn.id == pixInIO.id {
                    pixOut.outputPathList.remove(at: i)
                    break
                }
            }
            pixInIO.inputList = []
            pixelKit.logger.log(node: self, .info, .connection, "Disonnected Single: \(pixOut.name)")
        }
        if let newPixOut = newInPix {
            guard newPixOut.id != self.id else {
                pixelKit.logger.log(node: self, .error, .connection, "Can't connect to self.")
                return
            }
            var pixOut = newPixOut as! (NODE & NODEOutIO)
            pixInIO.inputList = [pixOut]
            pixOut.outputPathList.append(NODEOutPath(nodeIn: pixInIO, inIndex: 0))
            pixelKit.logger.log(node: self, .info, .connection, "Connected Single: \(pixOut.name)")
            connected()
        } else {
            disconnected()
        }
    }
    
    func setNeedsConnectMerger(new newInPix: (NODE & NODEOut)?, old oldInPix: (NODE & NODEOut)?, second: Bool) {
        guard var pixInIO = self as? NODE & NODEInIO else { pixelKit.logger.log(node: self, .error, .connection, "NODEIn's Only"); return }
        guard let pixInMerger = self as? NODEInMerger else { return }
        if let oldPixOut = oldInPix {
            var pixOut = oldPixOut as! (NODE & NODEOutIO)
            for (i, pixOutPath) in pixOut.outputPathList.enumerated() {
                if pixOutPath.nodeIn.id == pixInIO.id {
                    pixOut.outputPathList.remove(at: i)
                    break
                }
            }
            pixInIO.inputList = []
            pixelKit.logger.log(node: self, .info, .connection, "Disonnected Merger: \(pixOut.name)")
        }
        if let newPixOut = newInPix {
            if var pixOutA = (!second ? newPixOut : pixInMerger.inputA) as? (NODE & NODEOutIO),
                var pixOutB = (second ? newPixOut : pixInMerger.inputB) as? (NODE & NODEOutIO) {
                pixInIO.inputList = [pixOutA, pixOutB]
                pixOutA.outputPathList.append(NODEOutPath(nodeIn: pixInIO, inIndex: 0))
                pixOutB.outputPathList.append(NODEOutPath(nodeIn: pixInIO, inIndex: 1))
                pixelKit.logger.log(node: self, .info, .connection, "Connected Merger: \(pixOutA.name), \(pixOutB.name)")
                connected()
            }
        } else {
            disconnected()
        }
    }
    
    func setNeedsConnectMulti(new newInPixs: [NODE & NODEOut], old oldInPixs: [NODE & NODEOut]) {
        guard var pixInIO = self as? NODE & NODEInIO else { pixelKit.logger.log(node: self, .error, .connection, "NODEIn's Only"); return }
        pixInIO.inputList = newInPixs
        for oldInPix in oldInPixs {
            if var input = oldInPix as? (NODE & NODEOutIO) {
                for (j, pixOutPath) in input.outputPathList.enumerated() {
                    if pixOutPath.nodeIn.id == pixInIO.id {
                        input.outputPathList.remove(at: j)
                        break
                    }
                }
            }
        }
        for (i, newInPix) in newInPixs.enumerated() {
            if var input = newInPix as? (NODE & NODEOutIO) {
                input.outputPathList.append(NODEOutPath(nodeIn: pixInIO, inIndex: i))
            }
        }
        if !newInPixs.isEmpty {
            pixelKit.logger.log(node: self, .info, .connection, "Connected Multi: \(newInPixs.map(\.name))")
            connected()
        } else {
            disconnected()
        }
    }
    
    func connected() {
        applyResolution { self.render() }
        if let nodeIn: NODEIn = self as? NODEIn {
            nodeIn.didUpdateInputConnections()
        }
    }
    
    func disconnected() {
        pixelKit.logger.log(node: self, .info, .connection, "Disconnected")
        removeRes()
        texture = nil
        if let nodeIn: NODEIn = self as? NODEIn {
            nodeIn.didUpdateInputConnections()
        }
    }
    
    // MARK: - Other
    
//    // MARK: Custom Linking
//
//    public func customLink(to pix: PIX) {
//        for customLinkedPix in customLinkedNodes {
//            if customLinkedPix.id == pix.id {
//                return
//            }
//        }
//        customLinkedNodes.append(pix)
//    }
//
//    public func customDelink(from pix: PIX) {
//        for (i, customLinkedPix) in customLinkedNodes.enumerated() {
//            if customLinkedPix.id == pix.id {
//                customLinkedNodes.remove(at: i)
//                return
//            }
//        }
//    }
    
    // MARK: Equals
    
    public static func ==(lhs: PIX, rhs: PIX) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static func !=(lhs: PIX, rhs: PIX) -> Bool {
        return lhs.id != rhs.id
    }
    
    public static func ==(lhs: PIX?, rhs: PIX) -> Bool {
        guard lhs != nil else { return false }
        return lhs!.id == rhs.id
    }
    
    public static func !=(lhs: PIX?, rhs: PIX) -> Bool {
        guard lhs != nil else { return false }
        return lhs!.id != rhs.id
    }
    
    public static func ==(lhs: PIX, rhs: PIX?) -> Bool {
        guard rhs != nil else { return false }
        return lhs.id == rhs!.id
    }
    
    public static func !=(lhs: PIX, rhs: PIX?) -> Bool {
        guard rhs != nil else { return false }
        return lhs.id != rhs!.id
    }
    
    public func isEqual(to node: NODE) -> Bool {
        self.id == node.id
    }
    
    // MARK: Clean
    
    public func destroy() {
        clearRender()
        pixelKit.render.remove(node: self)
        texture = nil
        bypass = true
        destroyed = true
        view.destroy()
        pixelKit.logger.log(.info, .pixelKit, "Destroyed node(name: \(name), typeName: \(typeName), id: \(id))")
//        #if DEBUG
//        if pixelKit.logger.level == .debug {
//            var pix: PIX = self
//            // TODO: - Test
//            if !isKnownUniquelyReferenced(&pix) { // leak?
//                fatalError("pix not released")
//            }
//        }
//        #endif
    }
    
    // MARK: - Codable
    
    enum PIXCodingKeys: CodingKey {
        case id
        case name
        case typeName
        case bypass
        case viewInterpolation
        case interpolation
        case extend
        case mipmap
        case compare
        case liveList
    }
    
    enum LiveTypeCodingKey: CodingKey {
        case type
    }

    private struct EmptyDecodable: Decodable {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PIXCodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        typeName = try container.decode(String.self, forKey: .typeName)
        bypass = try container.decode(Bool.self, forKey: .bypass)
        viewInterpolation = try container.decode(ViewInterpolation.self, forKey: .viewInterpolation)
        interpolation = try container.decode(PixelInterpolation.self, forKey: .interpolation)
        extend = try container.decode(ExtendMode.self, forKey: .extend)
        mipmap = MTLSamplerMipFilter(rawValue: try container.decode(UInt.self, forKey: .mipmap))!
        compare = MTLCompareFunction(rawValue: try container.decode(UInt.self, forKey: .compare))!
        
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.async {
            self.setupPIX()
            group.leave()
        }
        group.wait()
        
        var liveCodables: [LiveCodable] = []
        var liveListContainer = try container.nestedUnkeyedContainer(forKey: .liveList)
        var liveListContainerMain = liveListContainer
        while(!liveListContainer.isAtEnd) {
            let liveTypeContainer = try liveListContainer.nestedContainer(keyedBy: LiveTypeCodingKey.self)
            guard let liveType: LiveType = try? liveTypeContainer.decode(LiveType.self, forKey: .type) else {
                _ = try? liveListContainerMain.decode(EmptyDecodable.self)
                continue
            }
            let liveCodable: LiveCodable = try liveListContainerMain.decode(liveType.liveCodableType)
            liveCodables.append(liveCodable)
        }
        for liveCodable in liveCodables {
            guard let liveWrap: LiveWrap = liveList.first(where: { $0.typeName == liveCodable.typeName }) else { continue }
            liveWrap.setLiveCodable(liveCodable)
        }
        
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PIXCodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(typeName, forKey: .typeName)
        try container.encode(bypass, forKey: .bypass)
        try container.encode(viewInterpolation, forKey: .viewInterpolation)
        try container.encode(interpolation, forKey: .interpolation)
        try container.encode(extend, forKey: .extend)
        try container.encode(mipmap.rawValue, forKey: .mipmap)
        try container.encode(compare.rawValue, forKey: .compare)
        try container.encode(liveList.map({ $0.getLiveCodable() }), forKey: .liveList)
    }
    
}

public extension PIX {
    
    func addView() -> NODEView {
        addPixView()
    }
    
    func addPixView() -> PIXView {
        let pixelFormat: MTLPixelFormat = overrideBits?.pixelFormat ?? PixelKit.main.render.bits.pixelFormat
        let view = PIXView(pix: self, with: PixelKit.main.render, pixelFormat: pixelFormat)
        additionalViews.append(view)
        applyResolution {
            self.render()
        }
        return view
    }
    
    func removeView(_ view: NODEView) {
        additionalViews.removeAll { nodeView in
            nodeView == view
        }
    }
    
}

public extension NODEOut where Self: PIX & NODEOut & PIXViewable {
    
    func pixBypass(_ value: Bool) -> PIX & NODEOut {
        bypass = value
        return self
    }
    
    func pixTransparentBackground() -> PIX & NODEOut {
        pixView.checker = false
        return self
    }
    
    func pixCheckerBackground() -> PIX & NODEOut {
        pixView.checker = true
        return self
    }
    
    /// Placement of the view.
    ///
    /// Default is `.fit`
    func pixPlacement(_ placement: Placement) -> PIX & NODEOut {
        view.placement = placement
        return self
    }
    
    /// Interpolate determins what happens inbetween scaled pixels.
    ///
    /// Default is `.linear`
    func pixInterpolate(_ interpolation: PixelInterpolation) -> PIX & NODEOut {
        self.interpolation = interpolation
        return self
    }
    
    /// Extend determins what happens to pixels outside of zero to one bounds.
    ///
    /// Default is `.zero`
    func pixExtend(_ extend: ExtendMode) -> PIX & NODEOut {
        self.extend = extend
        return self
    }
    
}
