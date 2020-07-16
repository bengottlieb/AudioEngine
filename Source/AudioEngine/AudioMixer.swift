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
	public var startedAt: Date?

	public var fadeIn: AudioTrack.Fade = .linear(1)
	public var fadeOut: AudioTrack.Fade = .linear(1)

	public private(set) var channels: [String: AudioChannel] = [:]
	public var playingChannels: [AudioChannel] { Array(self.channels.values.filter( { $0.isPlaying }))}
	
	public func start() {
		let start = Date()
		self.startedAt = start
		channels.values.forEach { $0.start(at: start) }
	}

	public func stop() {
		channels.values.forEach { $0.stop() }
	}

	internal func register(channel: AudioChannel) {
		channels[channel.name] = channel
	}
}
