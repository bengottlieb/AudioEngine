//
//  RemoteAudio.swift
//  
//
//  Created by Ben Gottlieb on 7/30/21.
//

import Suite

public class RemoteAudio {
	public static let instance = RemoteAudio()
	
	enum RemoteAudioError: Error { case noURLProvided, failedToBuildTrack }
	
	public func track(from url: URL?) -> AnyPublisher<AudioTrack, Error> {
		guard let url = url else {
			return Fail(outputType: AudioTrack.self, failure: RemoteAudio.RemoteAudioError.noURLProvided).eraseToAnyPublisher()
		}
		return DataCache.diskCache.fetchFile(for: url)
			.tryMap {
				if let track = AudioTrack(url: $0) { return track }
				throw RemoteAudio.RemoteAudioError.failedToBuildTrack
			}
			.eraseToAnyPublisher()
	}
}