//
//  AudioTrackView.swift
//  
//
//  Created by Ben Gottlieb on 11/10/20.
//

import SwiftUI
import Suite
import Combine

struct ProgressRectangle: Shape {
	let progress: Double
	func path(in rect: CGRect) -> Path {
		var path = Path()
		
		path.addRect(CGRect(x: 0, y: 0, width: rect.width * CGFloat(progress), height: rect.height))
		return path
	}
}

public struct AudioTrackView: View {
	let source: AudioSource

	@State var errorReport: String?
	@State var samples: AudioAnalysis.Samples?
	@State var samplePublisher: AnyCancellable?
	@State var cancellable: AnyCancellable?
	@State var progress = 0.0
	@State var range: ClosedRange<TimeInterval>?
	
	public init(source: AudioSource, initialRange: ClosedRange<TimeInterval>? = nil) {
		self.source = source
		_range = State(initialValue: initialRange)
	}
	
	public var body: some View {
		GeometryReader() { proxy in
			Group() {
				if let errorReport = errorReport {
					Text(errorReport)
				} else if let samples = samples {
					ProgressRectangle(progress: progress)
						.fill(Color.red)
					Waveform(samples: samples.samples, maxSample: samples.max)
						.stroke(lineWidth: 0.5)
				} else {
					ActivityIndicatorView()
				}
			}
			.onAppear {
				self.samplePublisher = source.audioAnalysis?.samples(time: range, downscaleTo: Int(proxy.size.width))
					.sink(receiveCompletion: { result in }) { samples in
						self.samples = samples
					}
			}

		}
		.frame(height: 100)
		.onTapGesture {
			if source.isPlaying {
				source.pause(outro: .default, completion: nil)
			} else {
				try? source.play(transition: .default, completion: nil)
				self.cancellable = source.activePlayers.first?.progressPublisher.sink { time in
					if let duration = samples?.duration {
						progress = time / duration
					}
				}
			}
		}
	}
}

//struct SwiftUIView_Previews: PreviewProvider {
//	static var previews: some View {
//		SwiftUIView()
//	}
//}
