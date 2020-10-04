//
//  AudioTrack.Segue.swift
//  AudioEngine
//

import Foundation


extension AudioTrack {
	public struct Transition: Codable {
		public var intro: Segue
		public var outro: Segue?
		
		public enum State { case none, introing, outroing, inAndOutroing
			static func +(lhs: State, rhs: State) -> State {
				if lhs == rhs { return lhs }
				if lhs == .none { return rhs }
				if rhs == .none { return lhs }
				return .inAndOutroing
			}
		}
		
		
		public var duration: TimeInterval {
			max(intro.duration, (outro?.duration ?? 0))
		}
		
		public init(intro: Segue, outro: Segue? = nil) {
			self.intro = intro
			self.outro = outro
		}

		static public var `default` = Transition(intro: .default, outro: nil)
	}
	
	public enum Segue: Codable, Equatable { case abrupt, constantPowerFade(TimeInterval), linearFade(TimeInterval)
		enum CodingKeys: String, CodingKey { case name, duration }
		
		var exists: Bool { duration > 0 }
		
		static public var `default` = Segue.linearFade(0.2)
		static public var defaultDuck = Segue.linearFade(1.0)

		var name: String {
			switch self {
			case .abrupt: return "abrupt"
			case .constantPowerFade(_): return "constant"
			case .linearFade(_): return "linear"
			}
		}

		var duration: Double {
			switch self {
			case .abrupt: return 0
			case .constantPowerFade(let duration): return duration
			case .linearFade(let duration): return duration
			}
		}
		
		public init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let raw = try container.decode(String.self, forKey: .name)
			switch raw {
			case "abrupt": self = .abrupt
			case "linear":
				let duration = try container.decode(TimeInterval.self, forKey: .duration)
				self = .linearFade(duration)
			case "constantPower":
				let duration = try container.decode(TimeInterval.self, forKey: .duration)
				self = .constantPowerFade(duration)
			default: self = .linearFade(5)
			}
		}
		
		public func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			
			try container.encode(self.name, forKey: .name)
			try container.encode(duration, forKey: .duration)
		}
		
		public func normalized(forMaxDuration max: TimeInterval) -> Self {
			guard self.duration > max else { return self }
			switch self {
			case .linearFade(_): return .linearFade(max)
			case .constantPowerFade(_): return .constantPowerFade(max)
			case .abrupt: return self
			}
		}
		
		public static func ==(lhs: Segue, rhs: Segue) -> Bool {
			switch (lhs, rhs) {
			case (.abrupt, .abrupt): return true
			case (.linearFade(let lhDuration), .linearFade(let rhDuration)): return lhDuration == rhDuration
			case (.constantPowerFade(let lhDuration), .constantPowerFade(let rhDuration)): return lhDuration == rhDuration
			default: return false
			}
		}
	}
}
