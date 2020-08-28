//
//  AudioFilePlayer.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

class AudioFilePlayer: NSObject, AudioPlayer {
	var track: AudioTrack?
	var player: AVAudioPlayer?
	var currentVolume = 0.0
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
	
	deinit { self.stop() }
	
	@discardableResult
	func load(track: AudioTrack, into channel: AudioChannel) -> Self {
		if !track.url.existsOnDisk { print("Trying to play a missing file: \(track.url.path)") }
		self.track = track
		self.channel = channel
		return self
	}
	
	@discardableResult
	func start() throws -> Self {
		guard let track = self.track else { return self }
		if self.pausedAt != nil {
			self.resume()
			return self
		}
		
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
	
	func mute(to factor: Float, fading fade: AudioTrack.Fade = .default) {
		if self.muteFactor == factor { return }
		self.muteFactor = factor
		self.player?.setVolume(1.0 - muteFactor, fadeDuration: fade.duration ?? 0)
	}
	
	func pause(fadeOut fade: AudioTrack.Fade = .default) {
		if self.pausedAt != nil { return }
		self.pausedAt = Date()
		self.timers.forEach { $0.invalidate() }
		self.player?.setVolume(0.0, fadeDuration: fade.duration ?? 0)
		self.pauseTimer = Timer.scheduledTimer(withTimeInterval: fade.duration ?? 0, repeats: false) { _ in
			self.player?.pause()
		}
	}
	
	func resume(fadeIn fade: AudioTrack.Fade = .default) {
		guard let pausedAt = self.pausedAt else { return }
		let delta = abs(pausedAt.timeIntervalSinceNow)
		self.pausedAt = nil
		self.player?.play()
		self.player?.setVolume(Float(isMuted ? 0 : self.currentVolume), fadeDuration: fade.duration ?? 0)
		if let fireAt = endTimerFireDate {
			endTimerFireDate = fireAt.addingTimeInterval(delta)
			self.endTimer = Timer.scheduledTimer(withTimeInterval: abs(endTimerFireDate!.timeIntervalSinceNow), repeats: false) { _ in self.didFinishPlaying() }
		}
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
	
	func applyFade(in fadingIn: Bool, to volume: Double) {
		guard let track = self.track, let player = self.player else { return }
		let fade = fadingIn ? track.fadeIn : track.fadeOut
		let duration = track.duration(for: fade ?? .default)
		
		if duration > 0 {
			log("Fading \(self) from \(self.currentVolume) to \(volume)", .verbose)
			self.player?.volume = isMuted ? 0 : Float(self.currentVolume)
			self.currentVolume = volume
			self.player?.play()
			self.fadePlayer(from: Double(player.volume), to: volume, over: duration)
			if !fadingIn {
				self.endTimerFireDate = Date(timeIntervalSinceNow: duration)
				self.endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in self.didFinishPlaying() }
			}
		} else {
			if fadingIn { self.play(at: track.volume) }
		}
	}
	
	func fadePlayer(from fromVol: Double, to toVol: Double, over duration: TimeInterval) {
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
				let newVolume = fromVol + percentage * delta
				self.player?.volume = self.isMuted ? 0 : Float(newVolume)
			}
		}
	}
	
	func play(at volume: Double) {
		self.player?.volume = 0
		self.player?.play()
		self.currentVolume = volume
		self.player?.volume = isMuted ? 0 : Float(volume)
	}
}

extension AudioFilePlayer {
	func didFinishPlaying() { log("Finished playing \(track!)") }
	
	func didBeginFadeOut(_ duration: TimeInterval) {
		applyFade(in: false, to: 0)
	}
}
