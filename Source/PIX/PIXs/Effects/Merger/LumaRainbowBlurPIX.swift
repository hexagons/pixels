//
//  LumaRainbowBlurPIX.swift
//  PixelKit
//
//  Created by Anton Heestand on 2018-08-09.
//  Open Source - MIT License
//

import Foundation
import RenderKit
import CoreGraphics

@available(*, deprecated, message: "New PIX Name: LumaRainbowBlurPIX")
public typealias RainbowLumaBlurPIX = LumaRainbowBlurPIX

final public class LumaRainbowBlurPIX: PIXMergerEffect, PIXViewable, ObservableObject {
    
    override public var shaderName: String { return "effectMergerLumaRainbowBlurPIX" }
    
    // MARK: - Public Properties
    
    public enum RainbowLumaBlurStyle: String, Enumable {
        case circle
        case angle
        case zoom
        public var index: Int {
            switch self {
            case .circle: return 1
            case .angle: return 2
            case .zoom: return 3
            }
        }
        public var name: String {
            switch self {
            case .circle: return "Circle"
            case .angle: return "Angle"
            case .zoom: return "Zoom"
            }
        }
    }
    
    @LiveEnum(name: "Style") public var style: RainbowLumaBlurStyle = .angle
    @LiveFloat(name: "Radius", increment: 0.125) public var radius: CGFloat = 0.5
    @LiveEnum(name: "Quality") public var quality: SampleQualityMode = .mid
    @LiveFloat(name: "Angle", range: -0.5...0.5) public var angle: CGFloat = 0.0
    @LivePoint(name: "Position") public var position: CGPoint = .zero
    @LiveFloat(name: "Light", range: 0.0...2.0) public var light: CGFloat = 1.0
    
    // MARK: - Property Helpers
    
    public override var liveList: [LiveWrap] {
        [_style, _radius, _quality, _angle, _position, _light] + super.liveList
    }
    
    override public var values: [Floatable] {
        return [radius, angle, position, light]
    }
    
    public override var uniforms: [CGFloat] {
        return [CGFloat(style.index), radius * 32 * 10, CGFloat(quality.rawValue), angle, position.x, position.y, light]
    }
    
    // MARK: - Life Cycle
    
    public required init() {
        super.init(name: "Luma Rainbow Blur", typeName: "pix-effect-merger-luma-rainbow-blur")
        extend = .hold
    }
    
}

public extension NODEOut {
    
    func pixLumaRainbowBlur(style: LumaRainbowBlurPIX.RainbowLumaBlurStyle = .zoom,
                            radius: CGFloat,
                            angle: CGFloat = 0.0,
                            position: CGPoint = .zero,
                            light: CGFloat = 1.0,
                            quality: PIX.SampleQualityMode = .mid,
                            pix: () -> (PIX & NODEOut)) -> LumaRainbowBlurPIX {
        pixLumaRainbowBlur(pix: pix(), style: style, radius: radius, angle: angle, position: position, light: light, quality: quality)
    }
    func pixLumaRainbowBlur(pix: PIX & NODEOut,
                            style: LumaRainbowBlurPIX.RainbowLumaBlurStyle = .zoom,
                            radius: CGFloat,
                            angle: CGFloat = 0.0,
                            position: CGPoint = .zero,
                            light: CGFloat = 1.0,
                            quality: PIX.SampleQualityMode = .mid) -> LumaRainbowBlurPIX {
        let lumaRainbowBlurPix = LumaRainbowBlurPIX()
        lumaRainbowBlurPix.name = ":lumaRainbowBlur:"
        lumaRainbowBlurPix.inputA = self as? PIX & NODEOut
        lumaRainbowBlurPix.inputB = pix
        lumaRainbowBlurPix.style = style
        lumaRainbowBlurPix.radius = radius
        lumaRainbowBlurPix.angle = angle
        lumaRainbowBlurPix.position = position
        lumaRainbowBlurPix.light = light
        lumaRainbowBlurPix.quality = quality
        return lumaRainbowBlurPix
    }
    
}
