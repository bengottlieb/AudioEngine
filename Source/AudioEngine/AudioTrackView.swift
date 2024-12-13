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

public struct ScrollingAudioView: View {
	let trackView: AudioTrackView
	
	@State var contentWidth: CGFloat = 2000
	
	public init(source: AudioSource, initialRange: ClosedRange<TimeInterval>? = nil) {
		trackView = AudioTrackView(source: source, initialRange: initialRange)
	}
	
	public var body: some View {
		ScrollView(.horizontal) {
			trackView
				.frame(width: contentWidth)
		}
		.onPreferenceChange(AudioTrackView.AudioViewWidthKey.self) { width in
			contentWidth = width
		}
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
	@State var style: Waveform.Style = .line
	@State var idealWidth: CGFloat = 0
	@State var spacing: CGFloat = 2
	
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
					Waveform(samples: samples.samples, range: samples.range, spacing: spacing)
						.stroke(lineWidth: 0.5)
				} else {
					ProgressView()
				}
			}
			.onAppear {
				self.samplePublisher = source.audioAnalysis?.samples(time: range, downscaleTo: Int((source.duration ?? 30) * 30)) // Int(proxy.size.width / spacing))
					.sink(receiveCompletion: { result in
						switch result {
						case .finished: break
						case .failure(let err): self.errorReport = err.localizedDescription
						}
					}) { samples in
						self.samples = samples
						self.idealWidth = Waveform.width(for: samples.samples, spacing: spacing)
					}
			}
			.preference(key: AudioViewWidthKey.self, value: idealWidth)

		}
		.frame(height: 100)
		.onTapGesture {
			if source.isPlaying {
				source.pause(outro: .default, completion: nil)
			} else {
				try? source.play(track: nil, loop: nil, transition: .default, completion: nil)
				self.cancellable = source.activePlayers.first?.progressPublisher.sink { time in
					if let duration = samples?.duration {
						progress = time / duration
					}
				}
			}
		}
	}
	
	struct AudioViewWidthKey: PreferenceKey {
		typealias Value = CGFloat

		static var defaultValue: CGFloat = 0
		
		static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
			value = max(value, nextValue())
		}
	}

}
