//
//  SwiftUIView.swift
//  
//
//  Created by Ben Gottlieb on 12/27/20.
//

import SwiftUI

public struct Wave: Shape {
	// allow SwiftUI to animate the wave phase
	public var animatableData: Double {
		get { phase }
		set { self.phase = newValue }
	}
	
	public init(strength: Double, frequency: Double, phase: Double) {
		self.strength = strength
		self.frequency = frequency
		self.phase = phase
	}
	
	// how high our waves should be
	var strength: Double
	
	// how frequent our waves should be
	var frequency: Double
	
	// how much to offset our waves horizontally
	var phase: Double
	
	public func path(in rect: CGRect) -> Path {
		let path = UIBezierPath()
		
		// calculate some important values up front
		let width = Double(rect.width)
		let height = Double(rect.height)
		let midWidth = width / 2
		let midHeight = height / 2
		let oneOverMidWidth = 1 / midWidth
		
		// split our total width up based on the frequency
		let wavelength = width / frequency
		
		// start at the left center
		path.move(to: CGPoint(x: 0, y: midHeight))
		
		// now count across individual horizontal points one by one
		for x in stride(from: 0, through: width, by: 1) {
			// find our current position relative to the wavelength
			let relativeX = x / wavelength
			
			// find how far we are from the horizontal center
			let distanceFromMidWidth = x - midWidth
			
			// bring that into the range of -1 to 1
			let normalDistance = oneOverMidWidth * distanceFromMidWidth
			
			let parabola = 1 - pow(normalDistance, 4)
			
			// calculate the sine of that position, adding our phase offset
			let sine = sin(relativeX + phase)
			
			// multiply that sine by our strength to determine final offset, then move it down to the middle of our view
			let y = parabola * strength * sine + midHeight
			
			// add a line to here
			path.addLine(to: CGPoint(x: x, y: y))
		}
		
		return Path(path.cgPath)
	}
}
