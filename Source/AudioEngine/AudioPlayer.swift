//
//  Playable.swift
//  
//
//  Created by Ben Gottlieb on 7/15/20.
//

import Foundation

protocol AudioPlayer {
	var track: AudioTrack? { get }
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
	func pause(fadeOut: AudioTrack.Fade)
	func play(fadeIn: AudioTrack.Fade?) throws -> Self
	func mute(to factor: Float, fading: AudioTrack.Fade)
	func reset() 
}
