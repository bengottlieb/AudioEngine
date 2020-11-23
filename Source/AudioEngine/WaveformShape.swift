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
	
	public init(samples: [Double], maxSample: Double) {
		self.samples = samples
		self.maxSample = maxSample
	}
	
	public init(samples: [Float], maxSample: Float) {
		self.samples = samples.map { Double($0) }
		self.maxSample = Double(maxSample)
	}
	
	public func path(in rect: CGRect) -> Path {
		var path = Path()
		let scale = rect.width / CGFloat(samples.count)
		let minimumGraphAmplitude: CGFloat = 1 // we want to see at least a 1pt line for silence
		
		var maxAmplitude: CGFloat = 0.0 // we know 1 is our max in normalized data, but we keep it 'generic'
		let positionAdjustedGraphCenter = rect.size.height / 2
		
		for (x, sample) in samples.enumerated() {
			let xPos = CGFloat(x) * scale
			let invertedDbSample = pow(1 - CGFloat(sample), 2) // sample is in dB, linearly normalized to [0, 1] (1 -> -50 dB)
			let drawingAmplitude = max(minimumGraphAmplitude, invertedDbSample * rect.size.height)
			let drawingAmplitudeUp = positionAdjustedGraphCenter - drawingAmplitude
			let drawingAmplitudeDown = positionAdjustedGraphCenter + drawingAmplitude
			maxAmplitude = max(drawingAmplitude, maxAmplitude)
			
			path.move(to: CGPoint(x: xPos, y: drawingAmplitudeUp))
			path.addLine(to: CGPoint(x: xPos, y: drawingAmplitudeDown))
		}
		
		return path
	}
	
}
