//
//  Playable.swift
//  
//
//  Created by Ben Gottlieb on 7/15/20.
//

import Foundation

protocol AudioPlayer {
	func pause(fadeOut: AudioTrack.Fade)
	func play(fadeIn: AudioTrack.Fade?) throws
	func mute(to factor: Float, fading: AudioTrack.Fade)
	func reset()
	var isPlaying: Bool { get }
	var isMuted: Bool { get }
	var isDucked: Bool { get }
}

protocol AudioSource: AudioPlayer {
	var track: AudioTrack? { get }
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
}
