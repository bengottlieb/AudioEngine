//
//  Playable.swift
//  
//
//  Created by Ben Gottlieb on 7/15/20.
//

import Foundation

public struct PlayerState: OptionSet, CustomStringConvertible {
	public let rawValue: Int
	
	public init(rawValue: Int) { self.rawValue = rawValue }
	
	public static let introing = PlayerState(rawValue: 1 << 0)
	public static let playing = PlayerState(rawValue: 1 << 1)
	public static let outroing = PlayerState(rawValue: 1 << 2)
	public static let muted = PlayerState(rawValue: 1 << 3)
	public static let ducked = PlayerState(rawValue: 1 << 4)
	
	public var isTransitioning: Bool { contains(.introing) || contains(.outroing) }
	
	public var description: String {
		var text = ""
		
		if self.contains(.playing) { text += "playing, " }
		if self.contains(.introing) { text += "introing, " }
		if self.contains(.outroing) { text += "outroing, " }
		if self.contains(.muted) { text += "muted, " }
		if self.contains(.ducked) { text += "ducked, " }
		if text.isEmpty { return "Not Playing" }
		
		return text
	}

}

public protocol AudioPlayer {
	func pause(outro: AudioTrack.Segue?, completion: (() -> Void)?)
	func play(transition: AudioTrack.Transition, completion: (() -> Void)?) throws
	func mute(to factor: Float, segue: AudioTrack.Segue, completion: (() -> Void)?)
	func reset()
	var state: PlayerState { get }

	var activeTracks: [AudioTrack] { get }
	var activePlayers: [AudioPlayer] { get }
}

public extension AudioPlayer {
	var isPlaying: Bool { state != [] }
	var isMuted: Bool { state.contains(.muted) }
	var isDucked: Bool { state.contains(.ducked) }
	var isPlayingFullOn: Bool { state == .playing }
	
	var nonFadingTracks: [AudioTrack] {
		activePlayers.filter({ $0.isPlayingFullOn }).flatMap { $0.activeTracks }
	}
}

public protocol AudioSource: AudioPlayer {
	var track: AudioTrack? { get }
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
}
