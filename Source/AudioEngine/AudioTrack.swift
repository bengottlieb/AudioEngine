//
//  AudioTrack.swift
//  AudioEngine
//

import Foundation
import AVFoundation
import Suite

public struct AudioTrack: Codable, CustomStringConvertible, Equatable, Identifiable, Hashable {
	enum CodingKeys: String, CodingKey { case url, id, volume, name, duration, intro, outro }
	
	public let id: String

	public static var silenceURL = URL(fileURLWithPath: "/")
	public let url: URL
	public var volume: Float = 1.0
	public var name: String
	public var intro: Segue?
	public var outro: Segue?
	public let asset: AVURLAsset
	public var duration: TimeInterval = 0												// this is the actual duration the associated audio
	public var requestedRange: Range<TimeInterval>?													// if only part of it is required
	public var effectiveDuration: TimeInterval { requestedRange?.delta ?? duration }		// the total amount of time the sound should be played for
	public var isSilence: Bool { self.url == Self.silenceURL }
	
	public func hash(into hasher: inout Hasher) { self.id.hash(into: &hasher) }
	
	public var description: String { "\(name): \(Date.ageString(age: self.effectiveDuration, style: .short))"}
	public init(url: URL, name: String? = nil, id: String? = nil, volume: Float = 1.0, duration: TimeInterval? = nil, intro: Segue? = nil, outro: Segue? = nil) {
		self.asset = AVURLAsset(url: url)
		self.url = url
		self.volume = volume
		self.name = name ?? url.deletingPathExtension().lastPathComponent
		self.id = id?.isEmpty == false ? id! : UUID().uuidString
		self.duration = duration ?? CMTimeGetSeconds(asset.duration)
		self.intro = intro
		self.outro = outro
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		self.volume = try container.decode(Float.self, forKey: .volume)
		self.url = try container.decode(URL.self, forKey: .url)
		self.asset = AVURLAsset(url: self.url)
		self.name = try container.decode(String.self, forKey: .name)
		self.id = try container.decode(String.self, forKey: .id)
		self.duration = try container.decode(TimeInterval.self, forKey: .duration)
		self.intro = try? container.decode(Segue.self, forKey: .intro)
		self.outro = try? container.decode(Segue.self, forKey: .outro)
	}
	
	func adjustingFade(in intro: Segue?, out outro: Segue?) -> Self {
		var copy = self
		copy.intro = intro ?? self.intro
		copy.outro = outro ?? self.outro
		return copy
	}
	
	public func buildPlayer(in channel: AudioChannel, intro: Segue? = nil, outro: Segue? = nil) throws -> AudioSource {
		try AudioFilePlayer()
			.load(track: self.adjustingFade(in: intro, out: outro), into: channel)
			.preload()
	}
	
	static func silence(duration: TimeInterval) -> AudioTrack { AudioTrack(url: Self.silenceURL, name: "silence", volume: 0, duration: duration) }
	
	func duration(of fade: Segue?) -> TimeInterval {
		guard let duration = fade?.duration else { return 0 }
		if duration > self.duration / 2 { return self.duration / 2 }
		return duration
	}

	var maxFadeDuration: TimeInterval { self.effectiveDuration * 0.3 }
	public static func ==(lhs: AudioTrack, rhs: AudioTrack) -> Bool { lhs.url == rhs.url }
}
