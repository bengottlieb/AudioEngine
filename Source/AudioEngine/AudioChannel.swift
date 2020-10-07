//
//  AudioChannel.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite
import Combine

public class AudioChannel: ObservableObject, AudioPlayer {
	public let name: String
	
	@Published public private(set) var isPlaying = false
	@Published public private(set) var pausedAt: Date?
	@Published public var queue = AudioQueue()
	@Published public var currentTrack: AudioTrack?
	@Published public var currentDuration: TimeInterval = 0
	
	public var defaultChannelFadeIn: AudioTrack.Segue?
	public var defaultChannelFadeOut: AudioTrack.Segue?
	public var shouldCrossFade = true
	
	public static var mainChannelName = "Main"
	public var state: PlayerState { self.players.reduce([]) { $0.union($1.state) }}

	var totalPauseTime: TimeInterval = 0
	var startedAt: Date?
	var willTransitionAt: Date?

	public var canPlay: Bool { self.queue.isEmpty == false }
	public var currentlyPlaying: Set<AudioTrack> {
		Set(self.players.reduce([]) { $0 + (($1.isPlaying && $1.track != nil) ? [$1.track!] : []) })
	}
	
	public var activeTracks: [AudioTrack] { self.players.reduce([]) { $0 + $1.activeTracks } }
	public var activePlayers: [AudioPlayer] { self.players.reduce([]) { $0 + $1.activePlayers } }

	public var currentTrackIndex: Int?
	private var pendingTrackIndex: Int?
	
	//private var availablePlayers: Set<Player> = []
	private var currentPlayer: AudioSource? { didSet { self.currentTrack = currentPlayer?.track }}
	private var fadingOutPlayer: AudioSource?
	private weak var transitionTimer: Timer?
	private var players: [AudioSource] { [currentPlayer, fadingOutPlayer].compactMap { $0 }}
	
	var muteFactor: Float = 0.0 { didSet { self.mute(to: muteFactor) }}

	public static func channel(named name: String) -> AudioChannel {
		if let existing = AudioMixer.instance.channels[name] { return existing }
		
		let channel = AudioChannel(name: name)
		AudioMixer.instance.register(channel: channel)
		return channel
	}
	
	init(name: String) {
		self.name = name
	}
	
	public func play(transition: AudioTrack.Transition, completion: (() -> Void)? = nil) throws {
		if let current = self.currentPlayer {
			self.fadingOutPlayer?.pause(outro: .abrupt, completion: nil)
			if !current.state.contains(.outroing) {
				current.pause(outro: .abrupt, completion: nil)
			}
			self.fadingOutPlayer = current
			self.pausedAt = nil
			self.startedAt	= nil
			self.isPlaying = false
			self.currentPlayer = nil
		}
		
		if let pausedAt = self.pausedAt {
			self.pausedAt = nil
			let pauseDuration = abs(pausedAt.timeIntervalSinceNow)
			totalPauseTime += pauseDuration
			self.players.forEach { _ = try? $0.play(transition: transition, completion: nil) }
			if let transitionAt = self.willTransitionAt {
				willTransitionAt = transitionAt.addingTimeInterval(pauseDuration)
				transitionTimer = Timer.scheduledTimer(withTimeInterval: abs(willTransitionAt!.timeIntervalSinceNow), repeats: false) { _ in
					self.startNextTrack()
				}
			}
			log("resumed at: \(Date()), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(style: .centiseconds))")
		} else {
			if self.isPlaying { return }			// already playing
		//	self.clear()

			self.currentDuration = queue.totalDuration(crossFade: self.shouldCrossFade, intro: self.defaultChannelFadeIn, outro: self.defaultChannelFadeOut)
			self.startedAt = Date()
			log("starting channel \(self.name) at \(self.startedAt!)", .verbose)
			self.startNextTrack()
			self.isPlaying = true
			log("done setting up channel \(self.name)", .verbose)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration) { completion?() }
	}
	
	public func pause(outro: AudioTrack.Segue?, completion: (() -> Void)? = nil) {
		if self.state.contains(.outroing), outro != .abrupt { return }
		if self.pausedAt != nil || self.startedAt == nil {
			completion?()
			return
		}
		let duration = self.duration(of: outro)
		self.pausedAt = Date(timeIntervalSinceNow: duration)
		self.players.forEach { $0.pause(outro: outro, completion: nil) }
		self.transitionTimer?.invalidate()
		log("Paused at: \(self.pausedAt!), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(style: .centiseconds))")
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + duration) { comp() } }
	}
	
	func duration(of segue: AudioTrack.Segue?) -> TimeInterval {
		guard let duration = segue?.duration, duration > 0 else { return 0 }
		
		return min(timeRemaining, duration)
	}
	
	func playStateChanged() {
		self.objectWillChange.sendOnMainThread()
		AudioMixer.instance.playStateChanged()
	}
	
	public func reset() {
		self.players.forEach { $0.reset() }
		self.transitionTimer?.invalidate()
		self.pausedAt = nil
		self.startedAt = nil
		self.currentTrackIndex = nil
		self.isPlaying = false
		self.clear()
		self.queue = AudioQueue()
	}
	
	public func mute(to factor: Float = 1.0, segue: AudioTrack.Segue = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? segue : .abrupt
		self.players.forEach { $0.mute(to: factor, segue: actualFade, completion: nil) }
		DispatchQueue.main.asyncAfter(deadline: .now() + actualFade.duration) { completion?() }
	}
	
	private func clear() {
		self.totalPauseTime = 0
		self.pausedAt = nil
		self.currentPlayer?.pause(outro: .abrupt, completion: nil)
		self.currentPlayer = nil
	}
	
	public var timeElapsed: TimeInterval {
		self.players.reduce(0) { max($0, $1.timeElapsed) }
	}
	
	public var timeRemaining: TimeInterval {
		self.players.reduce(0) { max($0, $1.timeRemaining) }
	}
	
	public func setDucked(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		self.players.forEach { $0.setDucked(on: on, segue: segue, completion: nil) }
		if let comp = completion {
			DispatchQueue.main.asyncAfter(deadline: .now() + segue.duration, execute: comp)
		}
	}

	public func setMuted(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		self.players.forEach { $0.setMuted(on: on, segue: segue, completion: nil) }
		if let comp = completion {
			DispatchQueue.main.asyncAfter(deadline: .now() + segue.duration, execute: comp)
		}
	}

	public func setQueue(_ queue: AudioQueue) {
		self.queue = queue
	}
	
	public func enqueue(track: AudioTrack, intro: AudioTrack.Segue? = nil, outro: AudioTrack.Segue? = nil) {
		self.queue.append(track, intro: intro, outro: outro)
	}
	
	public func clearQueue() {
		self.pause(outro: .default)
		self.queue.clear()
	}
	
	public func toggle() {
		if self.isPlaying {
			self.pause(outro: .default)
		} else {
			try? self.play(transition: .default)
		}
	}
		
	public func enqueue(silence duration: TimeInterval) { self.enqueue(track: .silence(duration: duration)) }
	
	func ended() {
		guard let startedAt = self.startedAt else { return }
		self.pause(outro: .default)

		log("\(self) has ended. Took \(abs(startedAt.timeIntervalSinceNow)), expected \(self.currentDuration).", .verbose)
		self.startedAt = nil
	}
	
	func startNextTrack() {
		if let current = self.currentTrackIndex {
			self.currentTrackIndex = current + 1
		} else {
			self.currentTrackIndex = 0
		}
		
//		fadingOutPlayer = currentPlayer
//		currentPlayer = nil

		guard let index = self.currentTrackIndex, let track = self.queue[index] else {
			self.ended()
			return
		}
		
		transitionTimer?.invalidate()
		var transitionTime = track.duration
		if self.shouldCrossFade, let next = self.queue[index + 1] {
			let fadeOutDuration = track.duration(of: track.outro)
			let nextFadeIn = next.intro ?? self.defaultChannelFadeIn
			let fadeInDuration = next.duration(of: nextFadeIn)
			transitionTime -= (fadeInDuration + fadeOutDuration) / 2
		}
		
		do {
			currentPlayer = try self.newPlayer(for: track)
			try currentPlayer?.play(transition: .default, completion: nil)
			
			if self.isMuted { currentPlayer?.mute(to: 0, segue: .abrupt, completion: nil) }
			willTransitionAt = Date(timeIntervalSinceNow: transitionTime)
			transitionTimer = Timer.scheduledTimer(withTimeInterval: transitionTime, repeats: false, block: { _ in
				self.startNextTrack()
			})
		} catch {
			currentPlayer = nil
		}
	}
	
	func end(player: AudioPlayer?) {
		guard let player = player else { return }
		player.pause(outro: .abrupt, completion: nil)
	//	self.availablePlayers.insert(player)
	}
	
	func newPlayer(for track: AudioTrack) throws -> AudioSource {
//		if let next = self.availablePlayers.first {
//			self.availablePlayers.remove(next)
//			return next
//		}
		
		let player = try track.buildPlayer(in: self, intro: track.intro ?? defaultChannelFadeIn, outro: track.outro ?? defaultChannelFadeOut)
		player.mute(to: muteFactor, segue: .abrupt, completion: nil)
		return player
	}
	
	func track(at offset: TimeInterval) -> AudioTrack? {
		var remaining = abs(offset)
		var tracks = self.queue.tracks
		
		while let track = tracks.first {
			if remaining < track.effectiveDuration { return track }
			remaining -= track.effectiveDuration
			tracks.removeFirst()
		}
		return nil
	}
	
	func track(after: AudioTrack) -> AudioTrack? {
		if let index = self.queue.firstIndex(of: after), index < (self.queue.count - 1) { return self.queue[index + 1] }
		return nil
	}
}
