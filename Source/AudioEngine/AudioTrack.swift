//
//  AudioTrack.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

public struct AudioTrack: Codable, CustomStringConvertible, Equatable, Identifiable {
	enum CodingKeys: String, CodingKey { case url, volume, name, duration, fadeIn, fadeOut }
	
	public let id = UUID()
	
	public static var silenceURL = URL(fileURLWithPath: "/")
	public let url: URL
	public var volume = 1.0
	public var name: String
	public var fadeIn: Fade?
	public var fadeOut: Fade?
	public let asset: AVURLAsset
	public var duration: TimeInterval = 0												// this is the actual duration the associated audio
	public var requestedRange: Range<TimeInterval>?													// if only part of it is required
	public var effectiveDuration: TimeInterval { requestedRange?.delta ?? duration }		// the total amount of time the sound should be played for
	public var isSilence: Bool { self.url == Self.silenceURL }
	
	public var description: String { "\(name): \(Date.ageString(age: self.effectiveDuration, style: .short))"}
	public init(url: URL, name: String? = nil, volume: Double = 1.0, duration: TimeInterval? = nil, fadeIn: Fade? = nil, fadeOut: Fade? = nil) {
		self.asset = AVURLAsset(url: url)
		self.url = url
		self.volume = volume
		self.name = name ?? url.deletingPathExtension().lastPathComponent
		self.duration = duration ?? CMTimeGetSeconds(asset.duration)
		self.fadeIn = fadeIn
		self.fadeOut = fadeOut
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		self.volume = try container.decode(Double.self, forKey: .volume)
		self.url = try container.decode(URL.self, forKey: .url)
		self.asset = AVURLAsset(url: self.url)
		self.name = try container.decode(String.self, forKey: .name)
		self.duration = try container.decode(TimeInterval.self, forKey: .duration)
		self.fadeIn = try? container.decode(Fade.self, forKey: .fadeIn)
		self.fadeOut = try? container.decode(Fade.self, forKey: .fadeOut)
	}
	
	func adjustingFade(in fadeIn: Fade?, out fadeOut: Fade?) -> Self {
		var copy = self
		copy.fadeIn = fadeIn ?? self.fadeIn
		copy.fadeOut = fadeOut ?? self.fadeOut
		return self
	}
	
	func buildPlayer(in channel: AudioChannel, fadeIn: Fade?, fadeOut: Fade?) throws -> AudioPlayer {
		try AudioTrackPlayer()
			.load(track: self.adjustingFade(in: fadeIn, out: fadeOut), into: channel)
			.preload()

	}
	
	static func silence(duration: TimeInterval) -> AudioTrack { AudioTrack(url: Self.silenceURL, name: "silence", volume: 0, duration: duration) }
	
	func duration(for fade: Fade?) -> TimeInterval {
		guard let duration = fade?.duration else { return 0 }
		if duration > self.duration / 2 { return self.duration / 2 }
		return duration
	}

	var maxFadeDuration: TimeInterval { self.effectiveDuration * 0.3 }
	public static func ==(lhs: AudioTrack, rhs: AudioTrack) -> Bool { lhs.id == rhs.id }
}
