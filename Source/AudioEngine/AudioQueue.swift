//
//  AudioQueue.swift
//  AudioEngine
//
//  Created by Ben Gottlieb on 7/12/20.
//  Copyright © 2020 SleepSpace. All rights reserved.
//

import Foundation

/* [-------------------------------------------------------------------]		// total duration
1:	[- in -][-- main --][- out -]
2:							   [- in-][-- main --][-out-]
3:													   [-- in --][-- main --][- out -]

	The fade in and fade out times are considered part of the total duration

	When crossfading, a track's fade in will start such that the midpoint of the fade in will
	occur at the same time as the midpoint of the fade out.
*/

public struct AudioQueue {
	public var tracks: [AudioTrack]
	public var useLoops = false
	public var count: Int { tracks.count }
	public var last: AudioTrack? { self.tracks.last }
	public var isEmpty: Bool { tracks.isEmpty }

	public subscript(index: Int) -> AudioTrack? { index < tracks.count ? tracks[index] : nil }

	public func firstIndex(of track: AudioTrack?) -> Int? { 
		guard let track = track else { return nil }
		return tracks.firstIndex(of: track)
	}
	
	mutating public func clear() { self.tracks = [] }

	public init(tracks: [AudioTrack] = [], intro: AudioTrack.Segue? = nil, outro: AudioTrack.Segue? = nil, useLoops: Bool = false) {
		self.tracks = []
		self.useLoops = useLoops
		tracks.forEach {
			self.append($0, intro: intro, outro: outro)
		}
	}
	
	mutating public func dropFirst(count: Int = 1) {
		tracks = count >= tracks.count ? [] : Array(tracks.dropFirst(count))
	}
	
	mutating public func append(_ track: AudioTrack, intro: AudioTrack.Segue? = nil, outro: AudioTrack.Segue? = nil) {
		var newTrack = track.adjustingFade(in: intro, out: outro)
		if track.effectiveDuration > track.duration { useLoops = true }

		if useLoops, let lastTrack = self.tracks.last, lastTrack == track {
			newTrack = lastTrack
			newTrack.duration += track.duration
			self.tracks[self.tracks.count - 1] = newTrack.adjustingFade(in: lastTrack.intro, out: outro)
		} else {
			self.tracks.append(newTrack)
		}
	}
		
	public func totalDuration(crossFade: Bool = true, intro defaultIntro: AudioTrack.Segue? = nil, requiredIntro: Bool = false, outro defaultOutro: AudioTrack.Segue? = nil, requiredOutro: Bool = false) -> TimeInterval {
		
		var total: TimeInterval = 0
		
		for (track, index) in zip(tracks, tracks.indices) {
			var trackDuration = track.duration
			
			if !useLoops {
				let intro = track.intro ?? defaultIntro ?? .linearFade(2)
				let outro = track.outro ?? defaultOutro ?? .linearFade(2)
				let introDuration = track.duration(of: intro, in: self)
				let outroDuration = track.duration(of: outro, in: self)
				
				if index != 0, crossFade { trackDuration -= introDuration / 2 }
				if index != (tracks.count - 1), crossFade { trackDuration -= outroDuration / 2 }
			}

			total += trackDuration
		}
		return total
	}
}
