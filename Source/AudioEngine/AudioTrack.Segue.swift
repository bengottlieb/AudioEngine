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
	
	public enum FadeStyle: Codable { case linear, exponential(Double)
		func value(at t: Double) -> Double {
			precondition(t >= 0 && t <= 1)

			switch self {
			case .linear: return t
			case .exponential(let floor):
				if t == 0 { return floor }
				return floor + pow(100, min(t, 1) - 1)
			}
		}
	}
	
	public enum Segue: Codable, Equatable { case abrupt, constantPowerFade(TimeInterval), linearFade(TimeInterval), exponentialFade(TimeInterval, Double)
		var exists: Bool { duration > 0 }
		
		static public var `default` = Segue.linearFade(0.2)
		static public var defaultDuck = Segue.linearFade(1.0)

		var fadeStyle: FadeStyle {
			switch self {
			case .exponentialFade(_, let floor): return .exponential(floor)
			default: return .linear
			}
		}
		var name: String {
			switch self {
			case .abrupt: return "abrupt"
			case .constantPowerFade: return "constant"
			case .linearFade: return "linear"
			case .exponentialFade: return "exponential"
			}
		}

		var duration: Double {
			switch self {
			case .abrupt: return 0
			case .constantPowerFade(let duration): return duration
			case .linearFade(let duration): return duration
			case .exponentialFade(let duration, _): return duration
			}
		}
		
		public func normalized(forMaxDuration max: TimeInterval) -> Self {
			guard self.duration > max else { return self }
			switch self {
			case .linearFade(_): return .linearFade(max)
			case .exponentialFade(_, let floor): return .exponentialFade(max, floor)
			case .constantPowerFade(_): return .constantPowerFade(max)
			case .abrupt: return self
			}
		}
		
		public static func ==(lhs: Segue, rhs: Segue) -> Bool {
			switch (lhs, rhs) {
			case (.abrupt, .abrupt): return true
			case (.exponentialFade(let lhDuration, let lFloor), .exponentialFade(let rhDuration, let rFloor)): return lhDuration == rhDuration && lFloor == rFloor
			case (.linearFade(let lhDuration), .linearFade(let rhDuration)): return lhDuration == rhDuration
			case (.constantPowerFade(let lhDuration), .constantPowerFade(let rhDuration)): return lhDuration == rhDuration
			default: return false
			}
		}
	}
}
