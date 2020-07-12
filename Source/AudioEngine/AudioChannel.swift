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
	public var fadeIn: AudioTrack.Fade?
	public var fadeOut: AudioTrack.Fade?
	public var shouldCrossFade = false
	private var inheritedFadeIn: AudioTrack.Fade? { fadeIn ?? AudioMixer.instance.fadeIn }
	private var inheritedFadeOut: AudioTrack.Fade? { fadeOut ?? AudioMixer.instance.fadeOut }

	
	var playerFadingIn: AudioPlayer? { didSet { if playerFadingIn != oldValue { log("set fadingIn to \(playerFadingIn?.track?.name ?? "--")") }}}
	var playerCurrent: AudioPlayer? { didSet { if playerCurrent != oldValue { log("set current to \(playerCurrent?.track?.name ?? "--")") }}}
	var playerFadingOut: AudioPlayer? { didSet { if playerFadingOut != oldValue { log("set fadingOut to \(playerFadingOut?.track?.name ?? "--")") }}}
	var availablePlayers: Set<AudioPlayer> = []
	
	public static func channel(named name: String) -> AudioChannel {
		if let existing = AudioMixer.instance.channels[name] { return existing }
		
		let channel = AudioChannel(name: name)
		AudioMixer.instance.register(channel: channel)
		return channel
	}
	
	init(name: String) {
		self.name = name
	}
	
	func start(at date: Date) {
		self.startedAt = date
		self.play(next: false)
		self.isPlaying = true
	}
	
	func stop() {
		self.startedAt = nil
		self.isPlaying = false
	}
	
	public func enqueue(track: AudioTrack) {
		self.queue.append(track)
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
		
		log("\(self) has ended. Took \(abs(startedAt.timeIntervalSinceNow)), expected \(queue.totalDuration(crossFade: self.shouldCrossFade, fadeIn: self.inheritedFadeIn, fadeOut: self.inheritedFadeOut)).")
		self.startedAt = nil
	}
	
	func play(next: Bool, endingCurrent: Bool = false) {
		guard let offset = self.startedAt?.timeIntervalSinceNow, var track = self.track(at: offset) else {
			self.ended()
			return
		}
		
		if next {
			guard let nextTrack = self.track(after: track) else { return }
			track = nextTrack
		}
		
		let fadeIn = track.fadeIn ?? self.fadeIn ?? AudioMixer.instance.fadeIn
		let fadeOut = track.fadeOut ?? self.fadeOut ?? AudioMixer.instance.fadeOut
		
		if endingCurrent {
			self.end(player: self.playerFadingIn)
		}
		do {
			self.playerFadingIn = try self.newPlayer()
				.load(track: track, into: self)
				.start(fadeIn: fadeIn, fadeOut: fadeOut)
		} catch {
			self.playerFadingIn = nil
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
		if let index = self.queue.firstIndex(of: after), index < (self.queue.count - 1) { return self.queue.tracks[index + 1] }
		return nil
	}
}

extension AudioChannel {
	func isLastTrack(_ track: AudioTrack?) -> Bool {
		track == self.queue.last
	}

	func playbackStarted(for player: AudioPlayer) {
		log("Playback started for \(player.track?.name ?? "--")")
		assert(self.playerCurrent == nil || self.playerCurrent == player, "active player mismatch")
		self.playerCurrent = player
	}
	
	func fadeInCompleted(for player: AudioPlayer) {
		log("Fade In ended for \(player.track?.name ?? "--")")
		if player == self.playerFadingIn {
			self.playerFadingIn = nil
			self.playerCurrent = player
		}
	}

	func fadeOutBegan(for player: AudioPlayer) {
		log("Fade out started for \(player.track?.name ?? "--")")
		if player == self.playerCurrent {
			self.playerCurrent = nil
			self.playerFadingOut = player
			if shouldCrossFade, !isLastTrack(player.track) { self.play(next: true) }
		}
	}

	func playbackEnded(for player: AudioPlayer) {
		log("Playback ended for \(player.track?.name ?? "--")")
		if player == self.playerCurrent { self.playerCurrent = nil }
		if player == self.playerFadingIn { self.playerFadingIn = nil }
		if player == self.playerFadingOut { self.playerFadingOut = nil }

		if self.playerFadingIn == nil, self.playerCurrent == nil {
			if !isLastTrack(player.track) {
				self.play(next: false, endingCurrent: true)
			} else {
				self.ended()
			}
		}
	}
}
