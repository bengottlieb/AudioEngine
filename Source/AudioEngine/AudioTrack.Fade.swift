//
//  AudioTrack.Fade.swift
//  AudioEngine
//

import Foundation


extension AudioTrack {
	public enum Fade: Codable { case abrupt, constantPower(TimeInterval), linear(TimeInterval)
		enum CodingKeys: String, CodingKey { case name, duration }
		
		var exists: Bool { (duration ?? 0) > 0 }
		
		static public var `default` = Fade.linear(0.2)

		var name: String {
			switch self {
			case .abrupt: return "abrupt"
			case .constantPower(_): return "constant"
			case .linear(_): return "linear"
			}
		}

		var duration: Double? {
			switch self {
			case .abrupt: return nil
			case .constantPower(let duration): return duration
			case .linear(let duration): return duration
			}
		}
		
		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let raw = try container.decode(String.self, forKey: .name)
			switch raw {
			case "abrupt": self = .abrupt
			case "linear":
				let duration = try container.decode(TimeInterval.self, forKey: .duration)
				self = .linear(duration)
			case "constantPower":
				let duration = try container.decode(TimeInterval.self, forKey: .duration)
				self = .constantPower(duration)
			default: self = .linear(5)
			}
		}
		
		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			
			try container.encode(self.name, forKey: .name)
			if let duration = self.duration {
				try container.encode(duration, forKey: .duration)
			}
		}
		
		public func normalized(forMaxDuration max: TimeInterval) -> Self {
			guard let duration = self.duration, duration > max else { return self }
			switch self {
			case .linear(_): return .linear(max)
			case .constantPower(_): return .constantPower(max)
			case .abrupt: return self
			}
		}
		
	}
}
