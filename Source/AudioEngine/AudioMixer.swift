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

	public var fadeIn: AudioTrack.Fade = .linear(1)
	public var fadeOut: AudioTrack.Fade = .linear(1)
	public var isMuted: Bool {
		get { self.playingChannels.reduce(true) { $0 && $1.isMuted }}
		set { self.mute(to: newValue ? 1 : 0, fading: .default) }
	}
	
	public var allowRecording = false { didSet { self.updateSession() }}
	
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
		get { ! self.playingChannels.isEmpty && self.playingChannels.reduce(true) { $0 && $1.isDucked }}
		set {
			self.playingChannels.forEach { $0.muteFactor = newValue ? self.duckMuteFactor : 0 }
		}
	}
	
	public var duckMuteFactor: Float = 0.9
	public var currentlyPlaying: Set<AudioTrack> {
		Set(channels.values.reduce([]) { $0 + $1.currentlyPlaying })
	}

	public private(set) var channels: [String: AudioChannel] = [:]
	public var playingChannels: [AudioChannel] { Array(self.channels.values.filter( { $0.isPlaying }))}
	
	public func play(fadeIn fade: AudioTrack.Fade? = nil, completion: (() -> Void)? = nil) throws {
		channels.values.forEach { try? $0.play(fadeIn: fade) }
		DispatchQueue.main.asyncAfter(deadline: .now() + (fade?.duration ?? 0)) { completion?() }
	}
	
	public func mute(to factor: Float, fading fade: AudioTrack.Fade = .defaultDuck, completion: (() -> Void)? = nil) {
		let actualFade = self.isPlaying ? fade : .abrupt
		self.playingChannels.forEach { $0.mute(to: factor, fading: actualFade) }
		DispatchQueue.main.asyncAfter(deadline: .now() + (actualFade.duration ?? 0)) { completion?() }
	}

	
	public func pause(fadeOut fade: AudioTrack.Fade = .default, completion: (() -> Void)? = nil) {
		channels.values.forEach { $0.pause(fadeOut: fade) }
		DispatchQueue.main.asyncAfter(deadline: .now() + (fade.duration ?? 0)) { completion?() }
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
