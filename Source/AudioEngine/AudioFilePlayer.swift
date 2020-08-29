//
//  AudioFilePlayer.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

class AudioFilePlayer: NSObject, AudioSource {
	var track: AudioTrack?
	var player: AVAudioPlayer?
	var currentVolume: Float = 0.0
	var startedAt: TimeInterval?
	var pausedAt: Date?
	var isMuted: Bool { muteFactor == 1 }
	var isDucked: Bool { muteFactor < 1 && muteFactor > 0 }
	var muteFactor: Float = 0.0
	weak var channel: AudioChannel?
	
	var endTimerFireDate: Date?
	weak var fadeOutTimer: Timer?
	weak var endTimer: Timer?
	weak var volumeFadeTimer: Timer?
	weak var pauseTimer: Timer?
	private var timers: [Timer] { [fadeOutTimer, endTimer, volumeFadeTimer, pauseTimer].compactMap { $0 }}

	var isPlaying: Bool { startedAt != nil }
	
	var timeRemaining: TimeInterval {
		guard let player = self.player else { return 0 }
		return player.duration - player.currentTime
	}
	
	deinit {
		self.reset()
	}
	
	@discardableResult
	func load(track: AudioTrack, into channel: AudioChannel) -> Self {
		if !track.url.existsOnDisk { print("Trying to play a missing file: \(track.url.path)") }
		self.track = track
		self.channel = channel
		return self
	}
	
	var effectiveVolume: Float {
		self.currentVolume * (1.0 - self.muteFactor)
	}
	
	func play(fadeIn fade: AudioTrack.Fade?) throws {
		guard let track = self.track else { return }
		if let pausedAt = self.pausedAt {
			let delta = abs(pausedAt.timeIntervalSinceNow)
			self.pausedAt = nil
			
			if let duration = fade?.duration, duration > 0 {
				self.player?.volume = 0.0
				self.player?.play()
				self.player?.setVolume(self.effectiveVolume, fadeDuration: duration)
			} else {
				self.player?.setVolume(self.effectiveVolume, fadeDuration: 0)
				self.player?.play()
			}
			if let fireAt = endTimerFireDate {
				endTimerFireDate = fireAt.addingTimeInterval(delta)
				self.endTimer = Timer.scheduledTimer(withTimeInterval: abs(endTimerFireDate!.timeIntervalSinceNow), repeats: false) { _ in self.didFinishPlaying() }
			}
			return
		}
		
		try self.preload()

		let fadeIn = fade ?? track.fadeIn ?? self.channel?.fadeIn ?? .default
		if fadeIn.exists {
			self.apply(fadeIn, in: true, to: track.volume)
		} else {
			self.play(at: track.volume)
		}
		
		let duration = track.duration(for: track.fadeOut ?? .default)
		if duration > 0 {
			self.fadeOutTimer = Timer.scheduledTimer(withTimeInterval: track.effectiveDuration - duration, repeats: false) { _ in self.didBeginFadeOut(duration) }
		}
	}
	
	func mute(to factor: Float, fading fade: AudioTrack.Fade = .default) {
		if self.muteFactor == factor { return }
		self.muteFactor = factor
		self.player?.setVolume(1.0 - muteFactor, fadeDuration: fade.duration ?? 0)
	}
	
	func pause(fadeOut fade: AudioTrack.Fade = .default) {
		if self.pausedAt == nil {
			self.pausedAt = Date()
		}
		self.timers.forEach { $0.invalidate() }
		if let duration = fade.duration {
			self.player?.setVolume(0.0, fadeDuration: duration)
			self.pauseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
				self.player?.pause()
			}
		} else {
			self.player?.pause()
			self.player?.volume = 0.0
		}
	}
	
	override var description: String {
		if let track = self.track { return "Player: \(track)" }
		return "Empty Player"
	}
	
	func reset() {
		self.pause(fadeOut: .abrupt)
		self.player?.stop()
		self.fadeOutTimer?.invalidate()
		self.endTimer?.invalidate()
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
	
	func apply(_ fade: AudioTrack.Fade, in fadingIn: Bool, to volume: Float) {
		guard let track = self.track, let player = self.player else { return }
		let duration = track.duration(for: fade)
		
		if duration > 0 {
			log("Fading \(self) from \(self.currentVolume) to \(volume)", .verbose)
			self.player?.volume = isMuted ? 0 : Float(self.currentVolume)
			self.currentVolume = volume
			self.player?.play()
			self.fadePlayer(from: player.volume, to: volume, over: duration)
			if !fadingIn {
				self.endTimerFireDate = Date(timeIntervalSinceNow: duration)
				self.endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in self.didFinishPlaying() }
			}
		} else {
			if fadingIn { self.play(at: track.volume) }
		}
	}
	
	func fadePlayer(from fromVol: Float, to toVol: Float, over duration: TimeInterval) {
		let delta = toVol - fromVol
		let start = Date()
		self.volumeFadeTimer?.invalidate()
		self.player?.volume = isMuted ? 0 : Float(fromVol)
		self.volumeFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
			let elapsed = abs(start.timeIntervalSinceNow)
			let percentage = (elapsed / duration)
			if percentage >= 1 {
				self.player?.volume = self.isMuted ? 0 : Float(toVol)
				timer.invalidate()
			} else {
				let newVolume = fromVol + Float(percentage) * delta
				self.player?.volume = self.isMuted ? 0 : Float(newVolume)
			}
		}
	}
	
	func play(at volume: Float) {
		self.player?.volume = 0
		self.player?.play()
		self.currentVolume = volume
		self.player?.volume = isMuted ? 0 : volume
	}
}

extension AudioFilePlayer {
	func didFinishPlaying() { log("Finished playing \(track!)") }
	
	func didBeginFadeOut(_ duration: TimeInterval) {
		let fade = self.track?.fadeOut ?? self.channel?.fadeOut ?? .default
		apply(fade, in: false, to: 0)
	}
}
