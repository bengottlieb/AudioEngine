//
//  Playable.swift
//  
//
//  Created by Ben Gottlieb on 7/15/20.
//

import Foundation

protocol AudioPlayer {
	var track: AudioTrack? { get }
	func start() throws -> Self
	func stop()
	func load(track: AudioTrack, into channel: AudioChannel) throws -> Self
}
