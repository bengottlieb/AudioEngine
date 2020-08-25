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

public class AudioMixer: ObservableObject {
	public static let instance = AudioMixer()
	public var startedAt: Date? { self.playingChannels.first?.startedAt }

	public var fadeIn: AudioTrack.Fade = .linear(1)
	public var fadeOut: AudioTrack.Fade = .linear(1)
	public var isMuted: Bool {
		get { self.playingChannels.reduce(true) { $0 && $1.isMuted }}
		set { self.playingChannels.forEach { $0.isMuted = true }; self.objectWillChange.send() }
	}

	public private(set) var channels: [String: AudioChannel] = [:]
	public var playingChannels: [AudioChannel] { Array(self.channels.values.filter( { $0.isPlaying }))}
	
	public func start() {
		channels.values.forEach { $0.play() }
		self.objectWillChange.send()
	}
	
	public func pause() {
		channels.values.forEach { $0.pause() }
		self.objectWillChange.send()
	}

	public func stop() {
		channels.values.forEach { $0.stop() }
		self.objectWillChange.send()
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
