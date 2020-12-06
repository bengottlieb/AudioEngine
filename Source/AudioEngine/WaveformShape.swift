//
//  Waveform.swift
//  
//
//  Created by Ben Gottlieb on 11/7/20.
//

import SwiftUI

public struct Waveform: Shape {
	public let samples: [Double]
	public let maxSample: Double
	public var invertSamples = true
	public var style = Style.vertical
	public var minSpacing: CGFloat = Waveform.defaultSpacing
	
	public static func width<T>(for samples: [T], spacing: CGFloat = Waveform.defaultSpacing) -> CGFloat {
		CGFloat(samples.count) * spacing
	}

	public enum Style { case vertical, line }
	public static var defaultSpacing: CGFloat = 3
	
	public init(samples: [Double], max: Double, invert: Bool = true, spacing: CGFloat = Waveform.defaultSpacing) {
		self.samples = samples
		maxSample = max
		invertSamples = invert
		minSpacing = spacing
	}
	
	public init(samples: [Float], max: Float, invert: Bool = true, spacing: CGFloat = Waveform.defaultSpacing) {
		self.samples = samples.map { Double($0) }
		maxSample = Double(max)
		invertSamples = invert
		minSpacing = spacing
	}
	
	public func path(in rect: CGRect) -> Path {
		var path = Path()
		let scale = max(minSpacing, min(rect.width / CGFloat(samples.count), 2))
		let minimumGraphAmplitude: CGFloat = 1 // we want to see at least a 1pt line for silence
		
		var maxAmplitude: CGFloat = 0.0 // we know 1 is our max in normalized data, but we keep it 'generic'
		let positionAdjustedGraphCenter = rect.size.height / 2
		var lastPoint: CGPoint?
		
		for (x, sample) in samples.enumerated() {
			let amplitude = sample / maxSample
			let xPos = CGFloat(x) * scale
			let polarized = min(1, invertSamples ? 1 - CGFloat(amplitude) : CGFloat(amplitude))
			let invertedDbSample = pow(polarized, 2) // sample is in dB, linearly normalized to [0, 1] (1 -> -50 dB)
			let drawingAmplitude = max(minimumGraphAmplitude, invertedDbSample * rect.size.height * 0.5)
			let drawingAmplitudeUp = positionAdjustedGraphCenter - drawingAmplitude
			let drawingAmplitudeDown = positionAdjustedGraphCenter + drawingAmplitude
			maxAmplitude = max(drawingAmplitude, maxAmplitude)
			
			let highPoint = CGPoint(x: xPos, y: drawingAmplitudeUp)
			if style == .vertical {
				path.move(to: highPoint)
				path.addLine(to: CGPoint(x: xPos, y: drawingAmplitudeDown))
			} else {
				if lastPoint == nil {
					path.move(to: highPoint)
				} else {
					path.addLine(to: highPoint)
				}
				path.addLine(to: CGPoint(x: xPos + scale / 2, y: drawingAmplitudeDown))
				lastPoint = highPoint
			}
		}
		
		return path
	}
	
}
