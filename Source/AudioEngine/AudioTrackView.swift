//
//  AudioTrackView.swift
//  
//
//  Created by Ben Gottlieb on 11/10/20.
//

import SwiftUI
import Suite

public struct AudioTrackView: View {
	let audioTrack: AudioTrack
	let analysis: AudioAnalysis
	
	@State var errorReport: String?
	@State var waveShape: Waveform?
	
	public init(track: AudioTrack) {
		audioTrack = track
		analysis = AudioAnalysis(url: track.url)
	}
	
	public var body: some View {
		GeometryReader() { proxy in
			Group() {
				if let errorReport = errorReport {
					Text(errorReport)
				} else if let shape = waveShape {
					shape
						.stroke(lineWidth: 0.5)

				} else {
					ActivityIndicatorView()
				}
			}
			.onAppear {
				let width = Int(proxy.size.width)
				DispatchQueue.global(qos: .userInitiated).async {
					let range = 0...audioTrack.duration
					if let samples = analysis.read(in: range, downscaleTo: width) {
						DispatchQueue.main.async {
							self.waveShape = Waveform(samples: samples.samples, maxSample: samples.max)
						}
					} else {
						DispatchQueue.main.async {
							self.errorReport = "Failed to load \(audioTrack.url.lastPathComponent)"
						}
					}
				}
			}

		}
		.frame(height: 100)
	}
}

//struct SwiftUIView_Previews: PreviewProvider {
//	static var previews: some View {
//		SwiftUIView()
//	}
//}
