//
//  PIXModes.swift
//  PixelKit
//
//  Created by Anton Heestand on 2018-08-23.
//  Open Source - MIT License
//

#if !os(tvOS) && !targetEnvironment(simulator)
import MetalPerformanceShaders
#endif
import RenderKit
import CoreGraphics

extension PIX {
    
    public enum SampleQualityMode: Int, Codable, CaseIterable, Floatable {
        case bad = 2
        case low = 4
        case mid = 8
        case high = 16
        case extreme = 32
        case insane = 64
        case epic = 128
        public var floats: [CGFloat] { [CGFloat(rawValue)] }
        public init(floats: [CGFloat]) {
            self = Self.allCases.first(where: { $0.rawValue == Int(floats.first ?? 0.0) }) ?? Self.allCases.first!
        }
    }
    
}
