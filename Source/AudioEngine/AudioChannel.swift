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
	
	public var isPaused: Bool { self.pausedAt != nil }
	public var isMuted: Bool {
		get { self.muteFactor == 1 }
		set { self.muteFactor = newValue ? 1 : 0 }
	}
	public var isDucked: Bool { self.muteFactor < 1 && self.muteFactor > 0 }
	public var fadeIn: AudioTrack.Segue?
	public var fadeOut: AudioTrack.Segue?
	public var shouldCrossFade = true
	
	public static var mainChannelName = "Main"
	
	var totalPauseTime: TimeInterval = 0
	var startedAt: Date?
	var willTransitionAt: Date?

	public var canPlay: Bool { self.queue.isEmpty == false }
	public var currentlyPlaying: Set<AudioTrack> {
		Set(self.players.reduce([]) { $0 + $1.currentlyPlaying })
	}

	private var inheritedFadeIn: AudioTrack.Segue { fadeIn ?? AudioMixer.instance.fadeIn }
	private var inheritedFadeOut: AudioTrack.Segue { fadeOut ?? AudioMixer.instance.fadeOut }
	
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
	
	public func play(fadeIn fade: AudioTrack.Segue? = nil, completion: (() -> Void)? = nil) throws {
		if let pausedAt = self.pausedAt {
			self.pausedAt = nil
			let pauseDuration = abs(pausedAt.timeIntervalSinceNow)
			totalPauseTime += pauseDuration
			self.players.forEach { _ = try? $0.play(fadeIn: fade, completion: nil) }
			if let transitionAt = self.willTransitionAt {
				willTransitionAt = transitionAt.addingTimeInterval(pauseDuration)
				transitionTimer = Timer.scheduledTimer(withTimeInterval: abs(willTransitionAt!.timeIntervalSinceNow), repeats: false) { _ in
					self.startNextTrack()
				}
			}
			log("resumed at: \(Date()), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(style: .centiseconds))")
		} else {
			if self.isPlaying { return }			// already playing
			self.clear()

			self.currentDuration = queue.totalDuration(crossFade: self.shouldCrossFade, fadeIn: self.inheritedFadeIn, fadeOut: self.inheritedFadeOut)
			self.startedAt = Date()
			log("starting channel \(self.name) at \(self.startedAt!)", .verbose)
			self.startNextTrack()
			self.isPlaying = true
			log("done setting up channel \(self.name)", .verbose)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + (fade?.duration ?? 0)) { completion?() }
	}
	
	public func pause(fadeOut fade: AudioTrack.Segue = .default, completion: (() -> Void)? = nil) {
		if self.pausedAt != nil || self.startedAt == nil {
			completion?()
			return
		}
		self.pausedAt = Date(timeIntervalSinceNow: fade.duration ?? 0)
		self.players.forEach { $0.pause(fadeOut: fade, completion: nil) }
		self.transitionTimer?.invalidate()
		log("Paused at: \(self.pausedAt!), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(style: .centiseconds))")
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + (fade.duration ?? 0)) { comp() } }
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
	
	public func mute(to factor: Float = 1.0, fading fade: AudioTrack.Segue = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? fade : .abrupt
		self.players.forEach { $0.mute(to: factor, fading: actualFade, completion: nil) }
		DispatchQueue.main.asyncAfter(deadline: .now() + (actualFade.duration ?? 0)) { completion?() }
	}
	
	private func clear() {
		self.totalPauseTime = 0
		self.pausedAt = nil
		self.currentPlayer?.pause(fadeOut: .abrupt, completion: nil)
		self.currentPlayer = nil
	}
	
	public var timeElapsed: TimeInterval? {
		guard let startedAt = self.startedAt else { return nil }
		let date = self.pausedAt ?? Date()
		return abs(startedAt.timeIntervalSince(date)) - totalPauseTime
	}
	
	public var timeRemaining: TimeInterval {
		guard let elapsed = timeElapsed else { return 0 }
		return currentDuration - elapsed
	}
	
	public func setQueue(_ queue: AudioQueue) {
		self.queue = queue
	}
	
	public func enqueue(track: AudioTrack, fadeIn: AudioTrack.Segue? = nil, fadeOut: AudioTrack.Segue? = nil) {
		self.queue.append(track, fadeIn: fadeIn, fadeOut: fadeOut)
	}
	
	public func clearQueue() {
		self.pause()
		self.queue.clear()
	}
	
	public func toggle() {
		if self.isPlaying {
			self.pause()
		} else {
			try? self.play()
		}
	}
		
	public func enqueue(silence duration: TimeInterval) { self.enqueue(track: .silence(duration: duration)) }
	
	func ended() {
		guard let startedAt = self.startedAt else { return }
		self.pause()

		log("\(self) has ended. Took \(abs(startedAt.timeIntervalSinceNow)), expected \(self.currentDuration).", .verbose)
		self.startedAt = nil
	}
	
	func startNextTrack() {
		if let current = self.currentTrackIndex {
			self.currentTrackIndex = current + 1
		} else {
			self.currentTrackIndex = 0
		}
		
		fadingOutPlayer = currentPlayer
		currentPlayer = nil

		guard let index = self.currentTrackIndex, let track = self.queue[index] else {
			self.ended()
			return
		}
		
		var transitionTime = track.duration
		if self.shouldCrossFade, let next = self.queue[index + 1] {
			let fadeOutDuration = track.duration(for: track.fadeOut)
			let nextFadeIn = next.fadeIn ?? self.inheritedFadeIn
			let fadeInDuration = next.duration(for: nextFadeIn)
			transitionTime -= (fadeInDuration + fadeOutDuration) / 2
		}
		
		do {
			currentPlayer = try self.newPlayer(for: track)
			try currentPlayer?.play(fadeIn: .default, completion: nil)
			
			if self.isMuted { currentPlayer?.mute(to: 0, fading: .abrupt, completion: nil) }
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
		player.pause(fadeOut: .abrupt, completion: nil)
	//	self.availablePlayers.insert(player)
	}
	
	func newPlayer(for track: AudioTrack) throws -> AudioSource {
//		if let next = self.availablePlayers.first {
//			self.availablePlayers.remove(next)
//			return next
//		}
		
		let player = try track.buildPlayer(in: self, fadeIn: track.fadeIn ?? inheritedFadeIn, fadeOut: track.fadeOut ?? inheritedFadeOut)
		player.mute(to: muteFactor, fading: .abrupt, completion: nil)
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
