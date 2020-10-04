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

	public var isMuted: Bool {
		get { self.playingChannels.reduce(true) { $0 && $1.isMuted }}
		set { self.mute(to: newValue ? 1 : 0, segue: .default) }
	}
	
	public var allowRecording = false { didSet { self.updateSession() }}
	public var transitionState: AudioTrack.Transition.State { self.playingChannels.reduce(.none) { $0 + $1.transitionState }}

	init() {
		self.updateSession()
	}
	
	func updateSession() {
		let audioSession = AVAudioSession.sharedInstance()
		try? audioSession.setCategory(allowRecording ? .playAndRecord : .playback, options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker, .duckOthers])
		try? audioSession.setActive(true)
	}

	public var isPlaying: Bool { self.playingChannels.contains { $0.isPaused == false } }
	public var canPlay: Bool { self.channels.values.reduce(false) { $0 || $1.canPlay } }

	public var isDucked: Bool {
		get { !self.playingChannels.isEmpty && self.playingChannels.reduce(true) { $0 && $1.isDucked }}
		set {
			self.playingChannels.forEach { $0.muteFactor = newValue ? self.duckMuteFactor : 0 }
		}
	}
	
	public var duckMuteFactor: Float = 0.9
	public var currentlyPlaying: Set<AudioTrack> {
		Set(channels.values.reduce([]) { $0 + $1.currentlyPlaying })
	}
	public var currentlyPlayingNotFadingOut: Set<AudioTrack> {
		Set(channels.values.reduce([]) { $0 + $1.currentlyPlayingNotFadingOut })
	}

	public private(set) var channels: [String: AudioChannel] = [:]
	public var playingChannels: [AudioChannel] { Array(self.channels.values.filter( { $0.isPlaying }))}
	
	public func play(transition: AudioTrack.Transition, completion: (() -> Void)? = nil) throws {
		channels.values.forEach { try? $0.play(transition: transition) }
		DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration) { completion?() }
	}
	
	public func mute(to factor: Float, segue: AudioTrack.Segue = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? segue : .abrupt
		self.playingChannels.forEach { $0.mute(to: factor, segue: actualFade) }
		DispatchQueue.main.asyncAfter(deadline: .now() + actualFade.duration) { completion?() }
	}

	
	public func pause(outro: AudioTrack.Segue?, completion: (() -> Void)? = nil) {
		channels.values.forEach { $0.pause(outro: outro) }
		if let comp = completion { DispatchQueue.main.asyncAfter(deadline: .now() + (outro?.duration ?? 0)) { comp() } }
	}
	
	public func reset() {
		channels.values.forEach { $0.reset() }
	}
	
	func playStateChanged() {
		self.objectWillChange.sendOnMainThread()
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
}
