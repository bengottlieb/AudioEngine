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
		if let sample = URL.bundled(named: "sample.mp3") {
			try? FileManager.default.copyItem(at: sample, to: directory.appendingPathComponent("sample.mp3"))
		}
		
		self.files = try! FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
	}
}

struct ContentView: View {
	@StateObject var files = FileList()
	@ObservedObject var channel = AudioMixer.instance.mainChannel
	
	func play(_ url: URL) {
		guard let track = AudioTrack(url: url) else {
			logg("Failed to build track for \(url)")
			return
		}
		
//		channel.enqueue(track: track)
		try! channel.play(track: track)
	}
	
	var body: some View {
		Text("\(channel.state.description)")
		if let duration = channel.duration {
			Text("Duration: \(duration.durationString())")
		}
		
		List(files.files) { url in
			Button(action: { play(url) }) {
				HStack() {
					Text(url.lastPathComponent)
					Image(.play)
				}
			}
			.buttonStyle(PlainButtonStyle())
		}
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}
