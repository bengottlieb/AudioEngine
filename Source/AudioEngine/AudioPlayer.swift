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

public protocol AudioReporting {
	var state: PlayerState { get }
	var timeRemaining: TimeInterval { get }
	var timeElapsed: TimeInterval { get }
	var isPaused: Bool { get }

	///Active indicates players that are still playing their tracks (or tracks still in their players), regardless of fade-out status
	var activeTracks: [AudioTrack] { get }
	var allTracks: [AudioTrack] { get }
	var activePlayers: [AudioPlayer] { get }
	var allPlayers: [AudioPlayer] { get }
}

public extension AudioReporting {
	var isPlaying: Bool { state.contains(.playing) }
	var isMuted: Bool { state.contains(.muted) }
	var isDucked: Bool { state.contains(.ducked) }
	var isPlayingFullOn: Bool { state.contains(.playing) && !(state.contains(.outroing) || state.contains(.introing)) }
	
	/// Main tracks are those that are playing full-on, or those that are fading out if no other tracks are playing
	var mainTracks: [AudioTrack] {
		var players = self.activePlayers
		let outroingPlayers = players.filter({ !$0.state.contains(.outroing) && $0.state.contains(.playing) })
		if outroingPlayers.count != players.count {
			for player in outroingPlayers {
				if let index = players.firstIndex(where: { $0 === player }) { players.remove(at: index) }
			}
		}
		
		return players.flatMap { $0.activeTracks }
	}
	
	/// Non-Outroing tracks are those that are not fading out
	var nonOutroingTracks: [AudioTrack] {
		activePlayers.filter({ !$0.state.contains(.outroing) && $0.state.contains(.playing) }).flatMap { $0.activeTracks }
	}

	var nonOutroingPlayers: [AudioPlayer] {
		activePlayers.filter({ !$0.state.contains(.outroing) && $0.state.contains(.playing) }).flatMap { $0.activePlayers }
	}
	
	var currentTracks: [AudioTrack] {
		let players = allPlayers.compactMap { $0.allTracks.first }
		if players.isNotEmpty { return players }
		
		let all = allTracks
		return all.isEmpty ? [] : [all[0]]
	}
}

public protocol AudioPlayer: AnyObject, AudioReporting {
	func pause(outro: AudioTrack.Segue?, completion: (() -> Void)?)
	func play(track: AudioTrack?, loop: Bool?, transition: AudioTrack.Transition, completion: (() -> Void)?) throws
	func mute(to factor: Float, segue: AudioTrack.Segue, completion: (() -> Void)?)
	func reset()

	func setDucked(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)?)
	func setMuted(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)?)
	func seekTo(percent: Double)
	
	var progressPublisher: AnyPublisher<TimeInterval, Never> { get }
	var duration: TimeInterval? { get }
	var effectiveDuration: TimeInterval? { get }			// taking into account any loops
	var isLoopable: Bool { get }
    func setVolume(_ volume: Double, fadeDuration: TimeInterval)
}

public protocol ObservablePlayer: AudioPlayer, ObservableObject {
	
}

public protocol AudioSource: AudioPlayer {
	var id: String { get }
	var track: AudioTrack? { get }
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
	var audioAnalysis: AudioAnalysis? { get }
}

extension Array: AudioReporting where Element: AudioReporting {
	public var allTracks: [AudioTrack] { self.flatMap { ($0 as? AudioPlayer)?.activeTracks ?? [] }}
	public var allPlayers: [AudioPlayer] { self.flatMap { ($0 as? AudioPlayer)?.allPlayers ?? [] }}
	
	public var state: PlayerState { reduce(PlayerState()) { $0.union($1.state) } }
	public var timeRemaining: TimeInterval { reduce(0) { Swift.max($0, $1.timeRemaining) } }
	public var timeElapsed: TimeInterval { reduce(0) { Swift.max($0, $1.timeElapsed) } }
	
	public var activeTracks: [AudioTrack] { self.flatMap { ($0 as? AudioPlayer)?.activeTracks ?? [] } }
	public var activePlayers: [AudioPlayer] { self.flatMap { ($0 as? AudioPlayer)?.activePlayers ?? [] }  }
	
	public var isPaused: Bool { !self.activePlayers.filter({ $0.isPaused }).isEmpty }
}

protocol LoopableAudioPlayer: AudioPlayer {
}
