//
//  AudioFilePlayer.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

class AudioFilePlayer: NSObject, ObservablePlayer, URLLocatable {
	var track: AudioTrack?
	var player: AVAudioPlayer?
	var requestedVolume: Float = 0.0
	var outro: AudioTrack.Segue?
	var startedAt: Date?
	var endedAt: Date?
	var pausedAt: Date?
	var muteFactor: Float = 0.0
	var hasSentFinished = true
	weak var channel: AudioChannel?
	var id: String { track?.id ?? UUID().uuidString }
	var url: URL { track?.url ?? .blank }
	
	public var isPaused: Bool { pausedAt != nil }
	public var isLoopable = false
	var endTimerFireDate: Date?
	weak var fadeInTimer: Timer?
	weak var fadeOutTimer: Timer?
	weak var endTimer: Timer?
	weak var volumeFadeTimer: Timer?
	weak var pauseTimer: Timer?
	private var timers: [Timer] { [fadeInTimer, fadeOutTimer, endTimer, volumeFadeTimer, pauseTimer].compactMap { $0 }}
	public lazy var audioAnalysis: AudioAnalysis? = AudioAnalysis(url: track?.url ?? URL(fileURLWithPath: "/"))

	public var state: PlayerState = [] { didSet {
		guard state != oldValue, self.track != nil else { return }
		self.objectWillChange.send()
		self.channel?.playStateChanged()
	}}

	deinit {
		print("De-initing \(self)")
		self.reset()
	}
	
	override init() {
		super.init()
		print("Created \(self)")
	}
	
	var currentTimeValue = CurrentValueSubject<TimeInterval, Never>(0)
	lazy var progressPublisher: AnyPublisher<TimeInterval, Never> = currentTimeValue.eraseToAnyPublisher()
	
	@discardableResult
	func load(track: AudioTrack, into channel: AudioChannel) -> Self {
		if !track.url.existsOnDisk { logg("Trying to play a missing file: \(track.url.path)") }
		self.track = track
		self.channel = channel
		self.isLoopable = track.isLoopable
		return self
	}
	
	var effectiveVolume: Float {
		self.requestedVolume * (1.0 - self.muteFactor)
	}
	
	func play(track incomingTrack: AudioTrack? = nil, loop: Bool? = nil, transition: AudioTrack.Transition = .default, completion: (() -> Void)? = nil) throws {
		assert(Thread.isMainThread, "AudioFilePlayer.play(track:transition:completion) must be called on the main thread")
		hasSentFinished = false
		guard let track = incomingTrack ?? self.track else { return }
		if let pausedAt = self.pausedAt {
			let delta = abs(pausedAt.timeIntervalSinceNow)
			self.pausedAt = nil
			
			if transition.duration > 0 {
				self.player?.volume = 0.0
				self.state = [.introing, .playing]
				startPlayer()
				self.player?.setVolume(self.effectiveVolume, fadeDuration: transition.intro.duration)
				DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration) {
					self.state.remove(.introing)
					completion?()
				}
			} else {
				self.player?.setVolume(self.effectiveVolume, fadeDuration: 0)
				self.state = .playing
				startPlayer()
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
		self.isLoopable = track.isLoopable
//		let fadeIn = transition.intro ?? track.fadeIn ?? self.channel?.defaultChannelFadeIn ?? .default
		if transition.intro.duration > 0 {
			self.state = [.playing, .introing]
			self.apply(intro: transition.intro, to: self.requestedVolume)
		} else {
			self.state = .playing
			self.requestedVolume = track.volume
			self.play(at: self.effectiveVolume)
		}
		
		let duration = track.duration(of: track.outro ?? .default, in: channel?.queue)
		self.setupEndTimer(duration: track.effectiveDuration - duration, outroAt: track.outro?.duration)
	}

	func seekTo(percent: Double) {
		guard let player = player else { return }
		if isLoopable, let dur = effectiveDuration {
			let newElapsed = dur * percent
			self.startedAt = Date().addingTimeInterval(-newElapsed)
			return
		}
		player.seekTo(percent: percent)
		self.setupEndTimer(duration: player.duration - player.currentTime, outroAt: track?.outro?.duration)
	}
	
	func setupEndTimer(duration: TimeInterval, outroAt: TimeInterval?) {
		print("Setting up end timer: \(duration)")
		self.fadeOutTimer?.invalidate()
		self.endTimer?.invalidate()
		self.endTimerFireDate = Date(timeIntervalSinceNow: duration)
		self.endTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
			self.didFinishPlaying()
		}
		
		if let fadeDuration = outroAt, fadeDuration > 0 {
			self.fadeOutTimer = Timer.scheduledTimer(withTimeInterval: duration - fadeDuration, repeats: false) { _ in self.didBeginFadeOut(fadeDuration) }
		}
	}
	
	public var allTracks: [AudioTrack] { [track].compactMap() }
	public var allPlayers: [AudioPlayer] { [self] }
	
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
		guard let track = self.track, self.isPlaying else { return }
		let segue = outro ?? self.outro ?? .default
		if self.pausedAt == nil { self.pausedAt = Date(timeIntervalSinceNow: segue.duration) }
		self.invalidateTimers()
		
		let outroDuration = track.duration(of: segue, in: channel?.queue)
		if outroDuration > 0 {
			state.formUnion(.outroing)
			self.player?.setVolume(0.0, fadeDuration: outroDuration)
			self.pauseTimer = Timer.scheduledTimer(withTimeInterval: outroDuration, repeats: false) { _ in
				self.state.remove([.playing, .introing, .outroing])
				self.stopPlayer()
			}
		} else {
			self.state.remove([.playing, .introing, .outroing])
			self.stopPlayer()
			self.player?.volume = 0.0
		}
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + outroDuration) { comp() } }
		self.channel?.playStateChanged()
	}
	
	override var description: String {
		if let track = self.track { return "Player: \(track)" }
		return "Empty Player"
	}
	
	func reset() {
		pause(outro: .abrupt)
		didFinishPlaying()
		state = []
		stopPlayer()
		startedAt = nil
		endedAt = nil
		pausedAt = nil
		fadeOutTimer?.invalidate()
		endTimer?.invalidate()
	}
	
	@discardableResult
	func preload() throws -> Self {
		guard player == nil, let track = track, !track.isSilence else { return self }

		let newPlayer = try AVAudioPlayer(contentsOf: track.url)
		player = newPlayer
		newPlayer.prepareToPlay()
		if track.effectiveDuration > newPlayer.duration * 1.1 { newPlayer.numberOfLoops = -1 }
		logg(.break, .verbose)
		logg("ready to play \(track)", .verbose)
		return self
	}
	
	func apply(intro: AudioTrack.Segue? = nil, outro: AudioTrack.Segue? = nil, to volume: Float) {
		guard let track = self.track else { return }
		guard let segue = intro ?? outro else { return }
		let duration = track.duration(of: segue, in: channel?.queue)
		self.state.formUnion(intro == nil ? .outroing : .introing)
		self.fadeInTimer?.invalidate()
		
		if duration > 0 {
			self.player?.volume = self.effectiveVolume
			self.requestedVolume = volume
			startPlayer()
			self.fadePlayer(from: 0, to: self.effectiveVolume, over: duration)
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
        logg("Fading \(self) from \(fromVol) to \(toVol) over \(duration)", .verbose)

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
		if !self.state.contains(.playing) { self.state.insert(.playing) }
		self.player?.volume = 0
		startPlayer()
		self.requestedVolume = volume
		self.player?.volume = self.effectiveVolume
	}
	
	weak var positionTimer: Timer?
	func startPlayer() {
		self.player?.play()
		self.positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
			self.currentTimeValue.value = self.player?.currentTime ?? 0
		})
	}
	
	func stopPlayer() {
		self.player?.pause()
		self.positionTimer?.invalidate()
	}
}

extension AudioFilePlayer {
	func didFinishPlaying() {
		if !hasSentFinished, let track = self.track { AudioMixer.instance.finishedPlaying(track) }
		state = []
		hasSentFinished = true
		endedAt = Date()
		AudioMixer.instance.objectWillChange.send()
	}
	
	func didBeginFadeOut(_ duration: TimeInterval) {
		state.formUnion(.outroing)
		let segue = outro ?? track?.outro ?? channel?.defaultChannelFadeOut ?? .default
		apply(outro: segue, to: 0)
	}
	
	public var duration: TimeInterval? { return player?.duration ?? 0 }
	public var effectiveDuration: TimeInterval? { track?.effectiveDuration ?? player?.duration ?? 0 }
}

extension AudioFilePlayer: AudioSource {
	var timeRemaining: TimeInterval {
		guard let player = self.player else { return 0 }
		return player.duration - player.currentTime
	}
	
	var timeElapsed: TimeInterval {
		guard let startedAt = startedAt else { return 0 }
		
		let total = abs(startedAt.timeIntervalSinceNow)
		if let paused = pausedAt { return total - abs(paused.timeIntervalSinceNow) }
		return total
	}
	
	public func setDucked(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		if on {
			self.state.formUnion(.ducked)
		} else {
			self.state.remove(.ducked)
		}
		self.mute(to: on ? AudioMixer.instance.duckMuteFactor : 0.0, segue: segue, completion: completion)
	}

	public func setMuted(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		if on {
			self.state.formUnion(.muted)
		} else {
			self.state.remove(.muted)
		}
		self.mute(to: on ? 1.0 : 0.0, segue: segue, completion: completion)
	}

	
	var activePlayers: [AudioPlayer] { self.isPlaying ? [self] : [] }
	var activeTracks: [AudioTrack] {
		guard let track = self.track, self.isPlaying else { return [] }
		return [track]
	}
	

}

extension AudioFilePlayer: LoopableAudioPlayer {
    func loop() {
        player?.numberOfLoops = 1000000
        endTimer?.invalidate()
        endTimer = nil
    }
}
