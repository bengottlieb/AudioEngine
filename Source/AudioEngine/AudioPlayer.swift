//
//  AudioPlayer.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

class AudioPlayer: NSObject {
	var track: AudioTrack?
	var player: AVAudioPlayer?
	var currentVolume = 0.0
	var startedAt: TimeInterval?
	weak var channel: AudioChannel?
	weak var fadeOutTimer: Timer?
	weak var endTimer: Timer?

	var isPlaying: Bool { startedAt != nil }
	
	var timeRemaining: TimeInterval {
		guard let player = self.player else { return 0 }
		return player.duration - player.currentTime
	}
	
	deinit { self.stop() }
	
	@discardableResult
	func load(track: AudioTrack, into channel: AudioChannel, fadeIn: AudioTrack.Fade? = nil, fadeOut: AudioTrack.Fade? = nil) -> Self {
		self.track = track.adjustingFade(in: fadeIn, out: fadeOut)
		self.channel = channel
		return self
	}
	
	func stop() {
		self.player?.volume = 0
		self.player?.stop()
		self.fadeOutTimer?.invalidate()
		self.endTimer?.invalidate()
	}
	
	override var description: String {
		if let track = self.track { return "Player: \(track)" }
		return "Empty Player"
	}
	
	@discardableResult
	func preload() throws -> Self {
		guard self.player == nil, let track = self.track, !track.isSilence else { return self }

		let player = try AVAudioPlayer(contentsOf: track.url)
		self.player = player
		player.prepareToPlay()
		if track.duration > player.duration { player.numberOfLoops = -1 }
		log(.break, .verbose)
		log("ready to play \(track)", .verbose)
		return self
	}
	
	@discardableResult
	func start() throws -> Self {
		guard let track = self.track else { return self }
		try self.preload()

		if track.fadeIn?.exists == true {
			self.applyFade(in: true, to: track.volume)
		} else {
			self.play(at: track.volume)
		}
		
		let duration = track.duration(for: track.fadeOut ?? .default)
		if duration > 0 {
			self.fadeOutTimer = Timer.scheduledTimer(withTimeInterval: track.effectiveDuration - duration, repeats: false) { _ in self.didBeginFadeOut(duration) }
		}
		return self
	}

	func applyFade(in fadingIn: Bool, to volume: Double) {
		guard let track = self.track, let player = self.player else { return }
		let fade = fadingIn ? track.fadeIn : track.fadeOut
		let duration = track.duration(for: fade ?? .default)
		
		if duration > 0 {
			log("Fading \(self) from \(self.currentVolume) to \(volume)", .verbose)
			self.player?.volume = Float(self.currentVolume)
			self.currentVolume = volume
			self.player?.play()
			self.fadePlayer(from: Double(player.volume), to: volume, over: duration)
			if !fadingIn { self.endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in self.didFinishPlaying() } }
		} else {
			if fadingIn { self.play(at: track.volume) }
		}
	}
	
	weak var volumeFadeTimer: Timer?
	func fadePlayer(from fromVol: Double, to toVol: Double, over duration: TimeInterval) {
		let delta = toVol - fromVol
		let start = Date()
		self.volumeFadeTimer?.invalidate()
		self.player?.volume = Float(fromVol)
		self.volumeFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
			let elapsed = abs(start.timeIntervalSinceNow)
			let percentage = (elapsed / duration)
			if percentage >= 1 {
				self.player?.volume = Float(toVol)
				timer.invalidate()
			} else {
				let newVolume = fromVol + percentage * delta
				self.player?.volume = Float(newVolume)
			}
		}
	}
	
	func play(at volume: Double) {
		self.player?.volume = 0
		self.player?.play()
		self.currentVolume = volume
		self.player?.volume = Float(volume)
	}
}

extension AudioPlayer {
	func didFinishPlaying() { log("Finished playing \(track!)") }
	
	func didBeginFadeOut(_ duration: TimeInterval) {
		applyFade(in: false, to: 0)
	}
}
