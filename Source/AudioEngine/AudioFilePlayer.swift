//
//  AudioFilePlayer.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

class AudioFilePlayer: NSObject, AudioSource, ObservableObject {
	var track: AudioTrack?
	var player: AVAudioPlayer?
	var requestedVolume: Float = 0.0
	var outro: AudioTrack.Segue?
	var startedAt: Date?
	var endedAt: Date?
	var pausedAt: Date?
	var muteFactor: Float = 0.0
	weak var channel: AudioChannel?
	
	var endTimerFireDate: Date?
	weak var fadeInTimer: Timer?
	weak var fadeOutTimer: Timer?
	weak var endTimer: Timer?
	weak var volumeFadeTimer: Timer?
	weak var pauseTimer: Timer?
	private var timers: [Timer] { [fadeInTimer, fadeOutTimer, endTimer, volumeFadeTimer, pauseTimer].compactMap { $0 }}

	public var state: PlayerState = [] { didSet {
		guard state != oldValue, let track = self.track else { return }
		self.objectWillChange.send()
		self.channel?.playStateChanged()
		print("State for \(track.name) changed to \(state)")
	}}

	var timeRemaining: TimeInterval {
		guard let player = self.player else { return 0 }
		return player.duration - player.currentTime
	}
	
	var activePlayers: [AudioPlayer] { self.isPlaying ? [self] : [] }
	var activeTracks: [AudioTrack] {
		guard let track = self.track, self.isPlaying else { return [] }
		return [track]
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
		self.requestedVolume * (1.0 - self.muteFactor)
	}
	
	func play(transition: AudioTrack.Transition, completion: (() -> Void)? = nil) throws {
		guard let track = self.track else { return }
		if let pausedAt = self.pausedAt {
			let delta = abs(pausedAt.timeIntervalSinceNow)
			self.pausedAt = nil
			
			if transition.duration > 0 {
				self.player?.volume = 0.0
				self.state = [.introing, .playing]
				self.player?.play()
				self.player?.setVolume(self.effectiveVolume, fadeDuration: transition.intro.duration)
				DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration) {
					self.state.remove(.introing)
					completion?()
				}
			} else {
				self.player?.setVolume(self.effectiveVolume, fadeDuration: 0)
				self.state = .playing
				self.player?.play()
				completion?()
			}
			if let fireAt = endTimerFireDate { self.setupEndTimer(duration: abs(fireAt.addingTimeInterval(delta).timeIntervalSinceNow), outroAt: track.outro?.duration) }
			self.channel?.playStateChanged()
			return
		}
		
		try self.preload()
		self.startedAt = Date()
		self.endedAt = nil
		self.requestedVolume = track.volume
//		let fadeIn = transition.intro ?? track.fadeIn ?? self.channel?.defaultChannelFadeIn ?? .default
		if transition.intro.duration > 0 {
			self.state = [.playing, .introing]
			self.apply(intro: transition.intro, to: self.requestedVolume)
		} else {
			self.state = .playing
			self.requestedVolume = track.volume
			self.play(at: self.effectiveVolume)
		}
		
		let duration = track.duration(of: track.outro ?? .default)
		self.setupEndTimer(duration: track.effectiveDuration - duration, outroAt: track.outro?.duration)
	}
	
	func setupEndTimer(duration: TimeInterval, outroAt: TimeInterval?) {
		self.fadeOutTimer?.invalidate()
		self.endTimer?.invalidate()
		self.endTimerFireDate = Date(timeIntervalSinceNow: duration)
		self.endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in self.didFinishPlaying() }
		
		if let fadeDuration = outroAt, fadeDuration > 0 {
			self.fadeOutTimer = Timer.scheduledTimer(withTimeInterval: duration - fadeDuration, repeats: false) { _ in self.didBeginFadeOut(fadeDuration) }
		}
	}
	
	func mute(to factor: Float, segue: AudioTrack.Segue = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? segue : .abrupt
		DispatchQueue.main.asyncAfter(deadline: .now() + actualFade.duration) { completion?() }
		if self.muteFactor == factor { return }
		self.muteFactor = factor
		self.player?.setVolume(self.effectiveVolume, fadeDuration: actualFade.duration)
		self.channel?.playStateChanged()
	}
	
	func invalidateTimers() {
		self.timers.forEach { $0.invalidate() }
	}
	
	func pause(outro: AudioTrack.Segue? = nil, completion: (() -> Void)? = nil) {
		if !self.isPlaying { return }
		let segue = outro ?? self.outro ?? .default
		if self.pausedAt == nil {
			self.pausedAt = Date()
		}
		self.invalidateTimers()
		if segue.duration > 0 {
			state.formUnion(.outroing)
			self.player?.setVolume(0.0, fadeDuration: segue.duration)
			self.pauseTimer = Timer.scheduledTimer(withTimeInterval: segue.duration, repeats: false) { _ in
				self.state.remove([.playing, .introing, .outroing])
				self.player?.pause()
			}
		} else {
			self.state.remove([.playing, .introing, .outroing])
			self.player?.pause()
			self.player?.volume = 0.0
		}
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + segue.duration) { comp() } }
		self.channel?.playStateChanged()
	}
	
	override var description: String {
		if let track = self.track { return "Player: \(track)" }
		return "Empty Player"
	}
	
	func reset() {
		self.pause(outro: .abrupt)
		self.state = []
		self.player?.stop()
		self.startedAt = nil
		self.endedAt = nil
		self.pausedAt = nil
		self.fadeOutTimer?.invalidate()
		self.endTimer?.invalidate()
	}
	
	@discardableResult
	func preload() throws -> Self {
		guard self.player == nil, let track = self.track, !track.isSilence else { return self }

		let player = try AVAudioPlayer(contentsOf: track.url)
		self.player = player
		player.prepareToPlay()
		if track.duration > player.duration * 1.1 { player.numberOfLoops = -1 }
		log(.break, .verbose)
		log("ready to play \(track)", .verbose)
		return self
	}
	
	func apply(intro: AudioTrack.Segue? = nil, outro: AudioTrack.Segue? = nil, to volume: Float) {
		guard let track = self.track, let player = self.player else { return }
		guard let segue = intro ?? outro else { return }
		let duration = track.duration(of: segue)
		self.state.formUnion(intro == nil ? .outroing : .introing)
		self.fadeInTimer?.invalidate()
		
		if duration > 0 {
			log("Fading \(self) from \(self.requestedVolume) to \(volume)", .verbose)
			self.player?.volume = self.effectiveVolume
			self.requestedVolume = volume
			self.player?.play()
			self.fadePlayer(from: player.volume, to: self.effectiveVolume, over: duration)
			self.fadeInTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
				self.state.remove([.introing, .outroing])
			}
		} else if intro == nil {
			self.didFinishPlaying()
		} else {
			self.requestedVolume = track.volume
			if outro == nil { self.play(at: self.effectiveVolume) }
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
		self.requestedVolume = volume
		self.player?.volume = self.effectiveVolume
	}
}

extension AudioFilePlayer {
	func didFinishPlaying() {
		log("Finished playing \(track!)")
		self.state = []
		self.endedAt = Date()
		AudioMixer.instance.objectWillChange.send()
	}
	
	func didBeginFadeOut(_ duration: TimeInterval) {
		self.state.formUnion(.outroing)
		let segue = self.outro ?? self.track?.outro ?? self.channel?.defaultChannelFadeOut ?? .default
		apply(outro: segue, to: 0)
	}
}
