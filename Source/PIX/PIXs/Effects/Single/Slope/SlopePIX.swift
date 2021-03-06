//
//  SlopePIX.swift
//  PixelKit
//
//  Created by Anton Heestand on 2018-09-06.
//  Open Source - MIT License
//

import Foundation
import CoreGraphics
import RenderKit
import Resolution

final public class SlopePIX: PIXSingleEffect, PIXViewable {
    
    override public var shaderName: String { return "effectSingleSlopePIX" }
    
    // MARK: - Public Properties
    
    @LiveFloat("amplitude", range: 0.0...100.0, increment: 10.0) public var amplitude: CGFloat = 1.0
    
    // MARK: - Property Helpers
    
    public override var liveList: [LiveWrap] {
        [_amplitude]
    }
    
    override public var values: [Floatable] {
        return [amplitude]
    }
    
    // MARK: - Life Cycle
    
    public required init() {
        super.init(name: "Slope", typeName: "pix-effect-single-slope")
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    
}

public extension NODEOut {
    
    func pixSlope(_ amplitude: CGFloat = 1.0) -> SlopePIX {
        let slopePix = SlopePIX()
        slopePix.name = ":slope:"
        slopePix.input = self as? PIX & NODEOut
        slopePix.amplitude = amplitude
        return slopePix
    }
    
}
