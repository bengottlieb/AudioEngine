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

	public subscript(index: Int) -> AudioTrack? { index < tracks.count ? tracks[index] : nil }

	public func firstIndex(of track: AudioTrack) -> Int? { tracks.firstIndex(of: track) }
	mutating public func clear() { self.tracks = [] }

	public init(tracks: [AudioTrack] = [], fadeIn: AudioTrack.Fade? = nil, fadeOut: AudioTrack.Fade? = nil, useLoops: Bool = false) {
		self.tracks = []
		self.useLoops = useLoops
		tracks.forEach {
			self.append($0, fadeIn: fadeIn, fadeOut: fadeOut)
		}
	}
	
	mutating public func append(_ track: AudioTrack, fadeIn: AudioTrack.Fade? = nil, fadeOut: AudioTrack.Fade? = nil) {
		var newTrack = track.adjustingFade(in: fadeIn, out: fadeOut)

		if useLoops, let lastTrack = self.tracks.last, lastTrack == track {
			newTrack = lastTrack
			newTrack.duration += track.duration
			newTrack.fadeOut = track.fadeOut
			self.tracks[self.tracks.count - 1] = newTrack
		} else {
			self.tracks.append(newTrack)
		}
	}
		
	public func totalDuration(crossFade: Bool = true, fadeIn defaultFadeIn: AudioTrack.Fade? = nil, requiredFadeIn: Bool = false, fadeOut defaultFadeOut: AudioTrack.Fade? = nil, requiredFadeOut: Bool = false) -> TimeInterval {
		
		var total: TimeInterval = 0
		
		for (track, index) in zip(tracks, tracks.indices) {
			var trackDuration = track.duration
			
			if !useLoops {
				let fadeIn = track.fadeIn ?? defaultFadeIn ?? .linear(2)
				let fadeOut = track.fadeOut ?? defaultFadeOut ?? .linear(2)
				let fadeInDuration = track.duration(for: fadeIn)
				let fadeOutDuration = track.duration(for: fadeOut)
				
				if index != 0, crossFade { trackDuration -= fadeInDuration / 2 }
				if index != (tracks.count - 1), crossFade { trackDuration -= fadeOutDuration / 2 }
			}

			total += trackDuration
		}
		return total
	}
}
