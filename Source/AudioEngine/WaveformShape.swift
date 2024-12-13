//
//  Waveform.swift
//  
//
//  Created by Ben Gottlieb on 11/7/20.
//

import SwiftUI
import Swift

func LOG(_ value: Double) -> Double {
	log(value)
}

public struct Waveform: Shape {
	public let samples: [Double]
	public let sampleRange: Range<Double>
	public var invertSamples = true
	public var style = Style.vertical
	public var minSpacing: CGFloat = Waveform.defaultSpacing
	public enum DrawingStyle: String, CaseIterable { case classic, log, scaled, linear }

	public static func width<T>(for samples: [T], spacing: CGFloat = Waveform.defaultSpacing) -> CGFloat {
		CGFloat(samples.count) * spacing
	}

	public enum Style { case vertical, line }
	public static var defaultSpacing: CGFloat = 3
	public let baseline = 40.0
	public var drawingStyle = DrawingStyle.classic

	public init(samples: [Double], range: Range<Double>, invert: Bool = false, spacing: CGFloat = Waveform.defaultSpacing, drawingStyle: DrawingStyle = .classic) {
		self.samples = samples
		sampleRange = range
		invertSamples = invert
		minSpacing = spacing
		self.drawingStyle = drawingStyle
	}
	
	public init(samples: [Float], range: Range<Float>, invert: Bool = false, spacing: CGFloat = Waveform.defaultSpacing, drawingStyle: DrawingStyle = .classic) {
		self.samples = samples.map { Double($0) }
		sampleRange = Double(range.lowerBound)..<Double(range.upperBound)
		invertSamples = invert
		minSpacing = spacing
		self.drawingStyle = drawingStyle
	}
	
	
	public func path(in rect: CGRect) -> Path {
		var path = Path()
		let scale = max(minSpacing, min(rect.width / CGFloat(samples.count), 2))
		let minimumGraphAmplitude: CGFloat = 1 // we want to see at least a 1pt line for silence
		
		var maxAmplitude: CGFloat = 0.0 // we know 1 is our max in normalized data, but we keep it 'generic'
		let positionAdjustedGraphCenter = rect.size.height / 2
		var lastPoint: CGPoint?
		let halfHeight = rect.size.height * 0.5
		
		for (x, sample) in samples.enumerated() {
			let amplitude = (sample + baseline) / (sampleRange.upperBound + baseline)
			let xPos = CGFloat(x) * scale
			
			let drawingAmplitude: CGFloat
			
			switch drawingStyle {
			case .classic:
				let polarized = min(1, invertSamples ? 1 - CGFloat(amplitude) : CGFloat(amplitude))
				let invertedDbSample = pow(polarized, 2) // sample is in dB, linearly normalized to [0, 1] (1 -> -50 dB)
				drawingAmplitude = max(minimumGraphAmplitude, invertedDbSample * halfHeight)

			case .log:
				let delta: Double = sample - baseline
				drawingAmplitude = sample > baseline ? CGFloat(LOG(delta) ) * (rect.size.height / 10) : 1

			case .scaled:
				drawingAmplitude = abs(CGFloat(amplitude)) * halfHeight
				
			case .linear:
				drawingAmplitude = halfHeight * CGFloat((sample - sampleRange.lowerBound) / sampleRange.delta)
			}
			
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
