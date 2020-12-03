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
	var silenceBaseline = 0.0
	
	public init(samples: [Double], max: Double, invert: Bool = true, silence: Double = 0.0) {
		self.samples = samples
		maxSample = max
		invertSamples = invert
		silenceBaseline = silence
	}
	
	public init(samples: [Float], max: Float, invert: Bool = true, silence: Double = 0.0) {
		self.samples = samples.map { Double($0) }
		maxSample = Double(max)
		invertSamples = invert
		silenceBaseline = silence
	}
	
	public func path(in rect: CGRect) -> Path {
		var path = Path()
		let scale = min(rect.width / CGFloat(samples.count), 2)
		let minimumGraphAmplitude: CGFloat = 1 // we want to see at least a 1pt line for silence
		
		var maxAmplitude: CGFloat = 0.0 // we know 1 is our max in normalized data, but we keep it 'generic'
		let positionAdjustedGraphCenter = rect.size.height / 2
		
		for (x, sample) in samples.enumerated() {
			let amplitude = (sample - silenceBaseline) / (maxSample - silenceBaseline)
			let xPos = CGFloat(x) * scale
			let polarized = min(1, invertSamples ? 1 - CGFloat(amplitude) : CGFloat(amplitude))
			let invertedDbSample = pow(polarized, 2) // sample is in dB, linearly normalized to [0, 1] (1 -> -50 dB)
			let drawingAmplitude = max(minimumGraphAmplitude, invertedDbSample * rect.size.height * 0.5)
			let drawingAmplitudeUp = positionAdjustedGraphCenter - drawingAmplitude
			let drawingAmplitudeDown = positionAdjustedGraphCenter + drawingAmplitude
			maxAmplitude = max(drawingAmplitude, maxAmplitude)
			
			path.move(to: CGPoint(x: xPos, y: drawingAmplitudeUp))
			path.addLine(to: CGPoint(x: xPos, y: drawingAmplitudeDown))
		}
		
		return path
	}
	
}
