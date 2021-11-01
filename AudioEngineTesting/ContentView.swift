//
//  ContentView.swift
//  AudioEngineTesting
//
//  Created by Ben Gottlieb on 7/12/20.
//

import SwiftUI
import Suite

class FileList: ObservableObject {
	@Published var files: [URL] = []
	
	init() {
		let directory = URL.document(named: "files")
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
		if let sample = URL.bundled(named: "sample.mp3") {
			try? FileManager.default.copyItem(at: sample, to: directory.appendingPathComponent("sample.mp3"))
		}

		if let sample = URL.bundled(named: "piano-cassical-10sec.mp3") {
			try? FileManager.default.copyItem(at: sample, to: directory.appendingPathComponent("piano-cassical-10sec.mp3"))
		}

		do {
			self.files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
		} catch {
			self.files = []
		}
	}
}

struct ContentView: View {
	@StateObject var files = FileList()
	@ObservedObject var channel = AudioMixer.instance.mainChannel
	@State var current: URL?
	
	func pause() {
		channel.pause(outro: .linearFade(2))
		current = nil
	}
	
	func play(_ url: URL) {
		guard let track = AudioTrack(url: url) else {
			Studio.logg("Failed to build track for \(url)")
			return
		}
		
		current = url
		
//		channel.enqueue(track: track)
		try! channel.play(track: track)
	}
	
	func loop(_ url: URL) {
		guard let track = AudioTrack(url: url) else {
			Studio.logg("Failed to build track for \(url)")
			return
		}
		
		current = url
//		channel.enqueue(track: track)
		
		let queue = AudioQueue(tracks: [track], intro: nil, outro: nil, useLoops: true)
		channel.setQueue(queue)
		try? channel.play()
	}
	
	var body: some View {
		Text("\(channel.state.description)")
		if let duration = channel.duration {
			Text("Duration: \(duration.durationString())")
		}
		
		List(files.files) { url in
			HStack() {
				Text(url.lastPathComponent)
				Spacer()
				if current == url {
					Button(action: { pause() }) {
						Image(.pause)
							.padding(.horizontal)
					}
					.buttonStyle(PlainButtonStyle())
				} else {
					Button(action: { play(url) }) {
						Image(.play)
							.padding(.horizontal)
					}
					.buttonStyle(PlainButtonStyle())

					Button(action: { loop(url) }) {
						Image(.arrow_clockwise)
							.padding(.horizontal)
					}
					.buttonStyle(PlainButtonStyle())
				}
			}
		}
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}
