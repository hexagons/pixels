//
//  CrossPIX.swift
//  PixelKit
//
//  Created by Hexagons on 2018-08-21.
//  Open Source - MIT License
//

import CoreGraphics
import RenderKit

public class CrossPIX: PIXMergerEffect {
    
    override open var shaderName: String { return "effectMergerCrossPIX" }
    
    // MARK: - Public Properties
    
    public var fraction: CGFloat = 0.5
    
    // MARK: - Property Helpers
    
    override public var values: [CoreValue] {
        return [fraction]
    }
    
    // MARK: - Life Cycle
    
    public required init() {
        super.init(name: "Cross", typeName: "pix-effect-merger-cross")
    }
    
}

public extension NODEOut {
    
    func _cross(with pix: PIX & NODEOut, fraction: CGFloat) -> CrossPIX {
        let crossPix = CrossPIX()
        crossPix.name = ":cross:"
        crossPix.inputA = self as? PIX & NODEOut
        crossPix.inputB = pix
        crossPix.fraction = fraction
        return crossPix
    }
    
}

public func cross(_ pixA: PIX & NODEOut, _ pixB: PIX & NODEOut, at fraction: CGFloat) -> CrossPIX {
    let crossPix = CrossPIX()
    crossPix.name = ":cross:"
    crossPix.inputA = pixA
    crossPix.inputB = pixB
    crossPix.fraction = fraction
    return crossPix
}
