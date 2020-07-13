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
	public private(set) var startedAt: Date?
	
	@Published public var isPlaying = false { didSet { if isPlaying != (startedAt != nil) { self.toggle() }}}
	@Published public var queue = AudioQueue()
	@Published public var currentTrack: AudioTrack?
	@Published public var currentDuration: TimeInterval = 0

	public var fadeIn: AudioTrack.Fade?
	public var fadeOut: AudioTrack.Fade?
	public var shouldCrossFade = true
	private var inheritedFadeIn: AudioTrack.Fade { fadeIn ?? AudioMixer.instance.fadeIn }
	private var inheritedFadeOut: AudioTrack.Fade { fadeOut ?? AudioMixer.instance.fadeOut }
	
	public var currentTrackIndex: Int?
	public var stoppedAt: TimeInterval = 0
	private var pendingTrackIndex: Int?
	
	private var availablePlayers: Set<AudioPlayer> = []
	private var currentPlayer: AudioPlayer? { didSet { self.currentTrack = currentPlayer?.track }}
	private var fadingOutPlayer: AudioPlayer?
	private weak var transitionTimer: Timer?
	

	public static func channel(named name: String) -> AudioChannel {
		if let existing = AudioMixer.instance.channels[name] { return existing }
		
		let channel = AudioChannel(name: name)
		AudioMixer.instance.register(channel: channel)
		return channel
	}
	
	init(name: String) {
		self.name = name
	}
	
	public func start(at date: Date = Date()) {
		if self.isPlaying { return }			// already playing
		self.currentDuration = queue.totalDuration(crossFade: self.shouldCrossFade, fadeIn: self.inheritedFadeIn, fadeOut: self.inheritedFadeOut)
		self.startedAt = date
		self.startNextTrack()
		self.isPlaying = true
	}
	
	public func stop() {
		self.stoppedAt = self.timeElapsed ?? 0
		self.fadingOutPlayer?.stop()
		self.currentPlayer?.stop()
		self.transitionTimer?.invalidate()
		
		self.startedAt = nil
		self.currentTrackIndex = nil
		self.isPlaying = false
	}
	
	public var timeElapsed: TimeInterval? {
		guard let startedAt = self.startedAt else { return nil }
		return abs(startedAt.timeIntervalSinceNow)
	}
	
	public var timeRemaining: TimeInterval {
		guard let startedAt = self.startedAt else { return 0 }
		return currentDuration - abs(startedAt.timeIntervalSinceNow)
	}
	
	public func enqueue(track: AudioTrack, fadeIn: AudioTrack.Fade? = nil, fadeOut: AudioTrack.Fade? = nil) {
		var newTrack = track
		
		if let fadeIn = fadeIn { newTrack.fadeIn = fadeIn }
		if let fadeOut = fadeOut { newTrack.fadeOut = fadeOut }
		self.queue.append(newTrack)
	}
	
	public func clearQueue() {
		self.stop()
		self.queue.clear()
	}
	
	func toggle() {
		if self.isPlaying {
			self.stop()
		} else {
			self.start(at: Date())
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
		
		let fadeOut = track.fadeOut ?? self.inheritedFadeOut
		let fadeIn = track.fadeIn ?? self.inheritedFadeIn

		var transitionTime = track.duration
		if self.shouldCrossFade, let next = self.queue[index + 1] {
			let fadeOutDuration = track.duration(for: fadeOut)
			let nextFadeIn = next.fadeIn ?? self.inheritedFadeIn
			let fadeInDuration = next.duration(for: nextFadeIn)
			transitionTime -= (fadeInDuration + fadeOutDuration) / 2
		}
		
		do {
			currentPlayer = try self.newPlayer()
				.load(track: track, into: self)
				.start(fadeIn: fadeIn, fadeOut: fadeOut)
			
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
		self.availablePlayers.insert(player)
	}
	
	func newPlayer() -> AudioPlayer {
		if let next = self.availablePlayers.first {
			self.availablePlayers.remove(next)
			return next
		}
		
		return AudioPlayer()
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

extension AudioChannel {
	func isLastTrack(_ track: AudioTrack?) -> Bool {
		track == self.queue.last
	}

	func playbackStarted(for player: AudioPlayer) {
		log("Playback started for \(player.track?.name ?? "--")", .verbose)
	}
	
	func fadeInCompleted(for player: AudioPlayer) {
		log("Fade In ended for \(player.track?.name ?? "--")", .verbose)
	}

	func fadeOutBegan(for player: AudioPlayer) {
		log("Fade out started for \(player.track?.name ?? "--")", .verbose)
	}

	func playbackEnded(for player: AudioPlayer) {
		log("Playback ended for \(player.track?.name ?? "--")", .verbose)
	}
}
