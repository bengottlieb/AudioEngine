//
//  RemoteAudio.swift
//  
//
//  Created by Ben Gottlieb on 7/30/21.
//

import Suite
import Combine
import Convey

public class RemoteAudio {
	public static let instance = RemoteAudio()
	
	enum RemoteAudioError: Error { case noURLProvided, failedToBuildTrack }
	
//	public func track(from url: URL?, name: String? = nil) async throws -> AudioTrack {
//		guard let url = url else {
//			return Fail(outputType: AudioTrack.self, failure: RemoteAudio.RemoteAudioError.noURLProvided).eraseToAnyPublisher()
//		}
//		
//		
//		return try await DataCache.instance.fetch(from: url)
//			.tryMap {
//				if let track =  { return track }
//				throw RemoteAudio.RemoteAudioError.failedToBuildTrack
//			}
//			.eraseToAnyPublisher()
//	}
}
