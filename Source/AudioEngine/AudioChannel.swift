//
//  AudioChannel.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite
import Combine

public class AudioChannel: ObservableObject {
	public let name: String
	
	@Published public private(set) var isPlaying = false
	@Published public private(set) var pausedAt: Date?
	@Published public var queue = AudioQueue()
	@Published public var currentTrack: AudioTrack?
	@Published public var currentDuration: TimeInterval = 0
	@Published public var isMuted = false
	
	public var isPaused: Bool { self.pausedAt != nil }
	public var fadeIn: AudioTrack.Fade?
	public var fadeOut: AudioTrack.Fade?
	public var shouldCrossFade = true
	
	var totalPauseTime: TimeInterval = 0
	var startedAt: Date?
	var willTransitionAt: Date?

	private var inheritedFadeIn: AudioTrack.Fade { fadeIn ?? AudioMixer.instance.fadeIn }
	private var inheritedFadeOut: AudioTrack.Fade { fadeOut ?? AudioMixer.instance.fadeOut }
	
	public var currentTrackIndex: Int?
	public var stoppedAt: TimeInterval?
	private var pendingTrackIndex: Int?
	
	//private var availablePlayers: Set<Player> = []
	private var currentPlayer: AudioPlayer? { didSet { self.currentTrack = currentPlayer?.track }}
	private var fadingOutPlayer: AudioPlayer?
	private weak var transitionTimer: Timer?
	private var players: [AudioPlayer] { [currentPlayer, fadingOutPlayer].compactMap { $0 }}

	public static func channel(named name: String) -> AudioChannel {
		if let existing = AudioMixer.instance.channels[name] { return existing }
		
		let channel = AudioChannel(name: name)
		AudioMixer.instance.register(channel: channel)
		return channel
	}
	
	init(name: String) {
		self.name = name
	}
	
	public func play() {
		if self.pausedAt != nil {
			self.resume()
			return
		}
		if self.isPlaying { return }			// already playing
		self.clear()

		self.currentDuration = queue.totalDuration(crossFade: self.shouldCrossFade, fadeIn: self.inheritedFadeIn, fadeOut: self.inheritedFadeOut)
		self.startedAt = Date()
		log("starting channel \(self.name) at \(self.startedAt!)", .verbose)
		self.startNextTrack()
		self.isPlaying = true
		log("done setting up channel \(self.name)", .verbose)
	}
	
	public func pause(over duration: TimeInterval = 0.2) {
		if self.pausedAt != nil || self.startedAt == nil { return }
		self.pausedAt = Date(timeIntervalSinceNow: duration)
		self.players.forEach { $0.pause(over: duration) }
		self.transitionTimer?.invalidate()
		log("Paused at: \(self.pausedAt!), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(includingNanoseconds: true))")
	}
	
	public func resume(over duration: TimeInterval = 0.2) {
		guard let pausedAt = self.pausedAt else { return }
		self.pausedAt = nil
		let pauseDuration = abs(pausedAt.timeIntervalSinceNow)
		totalPauseTime += pauseDuration
		self.players.forEach { $0.resume(over: duration) }
		if let transitionAt = self.willTransitionAt {
			willTransitionAt = transitionAt.addingTimeInterval(pauseDuration)
			transitionTimer = Timer.scheduledTimer(withTimeInterval: abs(willTransitionAt!.timeIntervalSinceNow), repeats: false, block: { _ in
				self.startNextTrack()
			})
		}
		log("resumed at: \(Date()), total pause time: \(self.totalPauseTime), time remaining: \(self.timeRemaining.durationString(includingNanoseconds: true))")
	}
	
	public func stop() {
		self.stoppedAt = self.timeElapsed ?? 0
		self.fadingOutPlayer?.stop()
		self.currentPlayer?.stop()
		self.transitionTimer?.invalidate()
		
		self.startedAt = nil
		self.currentTrackIndex = nil
		self.isPlaying = false
		self.clear()
	}
	
	private func clear() {
		self.totalPauseTime = 0
		self.pausedAt = nil
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
	
	public func enqueue(track: AudioTrack, fadeIn: AudioTrack.Fade? = nil, fadeOut: AudioTrack.Fade? = nil) {
		self.queue.append(track, fadeIn: fadeIn, fadeOut: fadeOut)
	}
	
	public func clearQueue() {
		self.stop()
		self.queue.clear()
	}
	
	public func toggle() {
		if self.isPlaying {
			self.pause()
		} else {
			self.play()
		}
	}
		
	public func enqueue(silence duration: TimeInterval) { self.enqueue(track: .silence(duration: duration)) }
	
	func ended() {
		guard let startedAt = self.startedAt else { return }
		self.stop()

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
		
//		let fadeOut = track.fadeOut ?? self.inheritedFadeOut
//		let fadeIn = track.fadeIn ?? self.inheritedFadeIn

		var transitionTime = track.duration
		if self.shouldCrossFade, let next = self.queue[index + 1] {
			let fadeOutDuration = track.duration(for: track.fadeOut)
			let nextFadeIn = next.fadeIn ?? self.inheritedFadeIn
			let fadeInDuration = next.duration(for: nextFadeIn)
			transitionTime -= (fadeInDuration + fadeOutDuration) / 2
		}
		
		do {
			currentPlayer = try self.newPlayer(for: track)
				.start()
			
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
		player.stop()
	//	self.availablePlayers.insert(player)
	}
	
	func newPlayer(for track: AudioTrack) throws -> AudioPlayer {
//		if let next = self.availablePlayers.first {
//			self.availablePlayers.remove(next)
//			return next
//		}
		
		return try track.buildPlayer(in: self, fadeIn: track.fadeIn ?? inheritedFadeIn, fadeOut: track.fadeOut ?? inheritedFadeOut)
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
