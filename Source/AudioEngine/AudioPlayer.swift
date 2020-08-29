//
//  Playable.swift
//  
//
//  Created by Ben Gottlieb on 7/15/20.
//

import Foundation

protocol AudioPlayer {
	func pause(fadeOut: AudioTrack.Fade, completion: (() -> Void)?)
	func play(fadeIn: AudioTrack.Fade?, completion: (() -> Void)?) throws
	func mute(to factor: Float, fading: AudioTrack.Fade, completion: (() -> Void)?)
	func reset()
	var isPlaying: Bool { get }
	var isMuted: Bool { get }
	var isDucked: Bool { get }
}

protocol AudioSource: AudioPlayer {
	var track: AudioTrack? { get }
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
}
