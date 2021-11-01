//
//  AudioMixer.swift
//  AudioEngine
//
//  Created by Ben Gottlieb on 7/6/20.
//  Copyright © 2020 SleepSpace. All rights reserved.
//

import Foundation
import AVFoundation
import Suite

public class AudioMixer: ObservableObject, AudioPlayer {
	public static let instance = AudioMixer()
	public var startedAt: Date? { self.playingChannels.first?.startedAt }

	public var allowRecording = false { didSet { self.updateSession() }}
	public var state: PlayerState { self.channels.values.reduce([]) { $0.union($1.state) }}
	public var finishedPlayingPublisher = PassthroughSubject<AudioTrack, Never>()
	private var isPausedDueToInterruption = false
	
	private var cancelBag: Set<AnyCancellable> = []
	
	init() {
		self.updateSession()
		AVAudioSession.interruptionNotification.publisher()
			.receive(on: RunLoop.main)
			.eraseToAnyPublisher()
			.sink { note in
				self.handleInterruption(note: note)
			}.store(in: &cancelBag)
		
	}
	
	func handleInterruption(note: Notification) {
		if let type = note.interruptionType {
			switch type {
			case .began:
				logg("AudioMixer Interrruption began")
				if !isPlaying { return }
				pause(outro: .abrupt, completion: nil)
				isPausedDueToInterruption = true
				
			case .ended:
				logg("AudioMixer Interrruption ended")
				if !isPausedDueToInterruption { return }
				try? play(track: nil, transition: .default, completion: nil)
				isPausedDueToInterruption = false
				
			@unknown default:
				logg("AudioMixer Unknown interruption kind")
			}
		}
	}
	
	func updateSession() {
		let audioSession = AVAudioSession.sharedInstance()
		try? audioSession.setCategory(allowRecording ? .playAndRecord : .playback, options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker, .duckOthers])
		try? audioSession.setActive(true)
	}

	public var canPlay: Bool { self.channels.values.reduce(false) { $0 || $1.canPlay } }

	public var duckMuteFactor: Float = 0.5
	public var activeTracks: [AudioTrack] { self.channels.values.reduce([]) { $0 + $1.activeTracks } }
	public var activePlayers: [AudioPlayer] { self.channels.values.reduce([]) { $0 + $1.activePlayers } }
	public var isPaused: Bool { !self.activePlayers.filter({ $0.isPaused }).isEmpty }

	public private(set) var channels: [String: AudioChannel] = [:]
	public var playingChannels: [AudioChannel] { Array(self.channels.values.filter( { $0.isPlaying }))}
	
	public var progressPublisher: AnyPublisher<TimeInterval, Never> { Just(0).eraseToAnyPublisher() }
	public var duration: TimeInterval? { channels.values.compactMap({ $0.duration }).max() }

	public func play(track: AudioTrack?, transition: AudioTrack.Transition = .default, completion: (() -> Void)? = nil) throws {
		assert(Thread.isMainThread, "AudionMixer.play(track:transition:completion) must be called on the main thread")
		channels.values.forEach { try? $0.play(track: track, transition: transition) }
		DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration) { completion?() }
	}

	public func seekTo(percent: Double) {
		channels.values.forEach { $0.seekTo(percent: percent) }
	}
	
	public func mute(to factor: Float, segue: AudioTrack.Segue = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? segue : .abrupt
		self.playingChannels.forEach { $0.mute(to: factor, segue: actualFade) }
		DispatchQueue.main.asyncAfter(deadline: .now() + actualFade.duration) { completion?() }
	}
	
	public func pause(outro: AudioTrack.Segue? = nil, completion: (() -> Void)? = nil) {
		channels.values.forEach { $0.pause(outro: outro) }
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + (outro?.duration ?? 0)) { comp() } }
	}
	
	public func reset() {
		channels.values.forEach { $0.reset() }
	}
	
	func playStateChanged() {
		self.objectWillChange.sendOnMain()
	}

	internal func register(channel: AudioChannel) {
		channels[channel.name] = channel
	}
	
	public var mainChannel: AudioChannel {
		if let main = channels[AudioChannel.mainChannelName] { return main }
		
		let newMain = AudioChannel(name: AudioChannel.mainChannelName)
		self.register(channel: newMain)
		
		return newMain
	}
	
	public var timeRemaining: TimeInterval {
		self.channels.values.reduce(0) { max($0, $1.timeRemaining) }
	}
	
	public var timeElapsed: TimeInterval {
		self.channels.values.reduce(0) { max($0, $1.timeElapsed) }
	}
	
	public func setDucked(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		self.channels.values.forEach { $0.setDucked(on: on, segue: segue, completion: nil) }
		if let comp = completion {
			DispatchQueue.main.asyncAfter(deadline: .now() + segue.duration, execute: comp)
		}
	}

	public func setMuted(on: Bool, segue: AudioTrack.Segue, completion: (() -> Void)? = nil) {
		self.channels.values.forEach { $0.setMuted(on: on, segue: segue, completion: nil) }
		if let comp = completion {
			DispatchQueue.main.asyncAfter(deadline: .now() + segue.duration, execute: comp)
		}
	}
	
	func finishedPlaying(_ track: AudioTrack) {
		finishedPlayingPublisher.send(track)
	}

	public var allTracks: [AudioTrack] { Array(channels.values).flatMap { $0.allTracks }}
	public var allPlayers: [AudioPlayer] { Array(channels.values).flatMap { $0.allPlayers }}

}

public extension Notification {
	var interruptionReason: AVAudioSession.InterruptionReason? {
		if #available(iOS 14.5, *) {
			guard let rawValue = userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt else { return nil }
			return AVAudioSession.InterruptionReason(rawValue: rawValue)
		} else {
			return nil
		}
	}

	var interruptionType: AVAudioSession.InterruptionType? {
		guard let rawValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return nil }
		return AVAudioSession.InterruptionType(rawValue: rawValue)
	}
}
