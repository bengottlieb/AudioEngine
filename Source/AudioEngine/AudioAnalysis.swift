//
//  AudioAnalysis.swift
//  
//
//  Created by Ben Gottlieb on 11/7/20.
//

import Foundation
import AVFoundation
import Accelerate


public class AudioAnalysis: ObservableObject, Identifiable {
	public enum AudioAnalysisError: Error { case failedToCreateBuffer, failedToReadBuffer, noAudioTrackFound, invalidAudioTrack, unableToConstructAsset, failedToCreateTrack, failedToLoadTrack, failedToSetupTrack }
	public enum State: Int, Comparable { case idle, failedToLoad, loading, loaded, sampling, sampled
		public static func <(lhs: State, rhs: State) -> Bool { lhs.rawValue < rhs.rawValue }
	}
	
	public let url: URL
	@Published public var state = State.idle
	@Published public var samples: Samples?
	@Published public var loadError: Error?
	public var id: URL { url }
	
	public var name: String { self.url.deletingPathExtension().lastPathComponent }

	var track: AVAssetTrack!
	var reader: AVAssetReader!
	var numberOfSamples = 0
	var numberOfChannels = 1
	var sampleRate: CMTimeScale = 1
	var cmDuration = CMTime()
	var duration: TimeInterval { TimeInterval(CMTimeGetSeconds(cmDuration)) }

	public struct Samples {
		public let max: Float
		public let samples: [Float]
	}
	
	public init(url: URL, andLoadSampleCount: Int? = 2000, range: ClosedRange<TimeInterval>? = nil) {
		self.url = url

		self.setup() { error in
			if let err = error {
				self.loadError = err
				self.state = .idle
			} else if let sampleCount = andLoadSampleCount {
				self.state = .loaded
				if let range = range {
					self.read(in: range, downscaleTo: sampleCount)
				} else {
					self.read(downscaleTo: sampleCount)
				}
			} else {
				self.state = .loaded
			}
		}
	}

	@discardableResult
	public func read(in requestedRange: ClosedRange<TimeInterval>, downscaleTo targetSamples: Int) -> Samples? {
		let start = min(1, requestedRange.lowerBound / duration)
		let end = min(1, requestedRange.upperBound / duration)
		let sampleRange = Int(Double(numberOfSamples / numberOfChannels) * start)...Int(Double(numberOfSamples / numberOfChannels) * end)
		
		return read(in: sampleRange, downscaleTo: targetSamples)
	}

	@discardableResult
	public func read(in requestedRange: ClosedRange<CMTime>, downscaleTo targetSamples: Int) -> Samples? {
		let start = requestedRange.lowerBound.percentage(of: cmDuration)
		let end = requestedRange.upperBound.percentage(of: cmDuration)
		let sampleRange = Int(Double(numberOfSamples / numberOfChannels) * start)...Int(Double(numberOfSamples / numberOfChannels) * end)
		
		return read(in: sampleRange, downscaleTo: targetSamples)
	}

	@discardableResult
	public func read(in requestedRange: ClosedRange<Int>? = nil, downscaleTo targetSamples: Int) -> Samples? {
		if self.duration.isZero || self.duration.isNaN {
			self.state = .failedToLoad
			return nil
		}
		
		switch state {
		case .idle, .failedToLoad, .loading, .sampling: return nil
		case .sampled: return samples
		case .loaded: break
		}

		self.state = .sampling
		let range = requestedRange ?? 0...numberOfSamples
		let start = CMTime(value: Int64(range.lowerBound), timescale: sampleRate)
		let duration = CMTime(value: Int64(range.count), timescale: sampleRate)
		let requestedSamples = range.upperBound - range.lowerBound
		
		reader.timeRange = CMTimeRange(start: start, duration: duration)
		let outputSettings: [String : Any] = [
			AVFormatIDKey: Int(kAudioFormatLinearPCM),
			AVLinearPCMBitDepthKey: 16,
			AVLinearPCMIsBigEndianKey: false,
			AVLinearPCMIsFloatKey: false,
			AVLinearPCMIsNonInterleaved: false
		]
		
		let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
		readerOutput.alwaysCopiesSampleData = false
		reader.add(readerOutput)

		var sampleMax: Float = 0
		let samplesPerPixel = max(1, requestedSamples / targetSamples)
		let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)

		var outputSamples: [Float] = []
		var sampleBuffer = Data()
		let totalSamples = requestedSamples//sampleBuffer.count / MemoryLayout<Int16>.size

		reader.startReading()
		defer { reader.cancelReading() }
		while reader.status == .reading {
			guard let readBuffer = readerOutput.copyNextSampleBuffer(), let buffer = CMSampleBufferGetDataBuffer(readBuffer) else { break }
			
			var bufferLength = 0
			var bufferPointer: UnsafeMutablePointer<Int8>?
			
			CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: &bufferLength, totalLengthOut: nil, dataPointerOut: &bufferPointer)
			sampleBuffer.append(UnsafeBufferPointer(start: bufferPointer, count: bufferLength))
			CMSampleBufferInvalidate(readBuffer)
			
			let downSampledLength = totalSamples / samplesPerPixel
			let samplesToProcess = downSampledLength * samplesPerPixel
			
			guard samplesToProcess > 0 else { continue }
			let processed = self.processSamples(from: &sampleBuffer, sampleMax: &sampleMax, samplesToProcess: samplesToProcess, downSampledLength: downSampledLength, samplesPerPixel: samplesPerPixel, filter: filter)
			outputSamples += processed
			if processed.count > 0 {
				sampleBuffer.removeFirst(processed.count * samplesPerPixel * MemoryLayout<Int16>.size)
			}
		}
		
		let remainingSamples = sampleBuffer.count / MemoryLayout<UInt16>.size
		if remainingSamples > 0 {
			let filter = [Float](repeating: 1.0 / Float(remainingSamples), count: remainingSamples)
			let chunk = self.processSamples(from: &sampleBuffer, sampleMax: &sampleMax, samplesToProcess: remainingSamples, downSampledLength: 1, samplesPerPixel: samplesPerPixel, filter: filter)
			
			outputSamples += chunk
		}
		
		let samples = outputSamples.map { $0 / silenceDbThreshold }
		let maxSample = samples.max() ?? 0
		self.samples = Samples(max: maxSample, samples: samples)
		
		self.state = .sampled
		return self.samples
	}
	
	private var silenceDbThreshold: Float { return -50.0 } // everything below -50 dB will be clipped
	func processSamples(from sampleBuffer: inout Data, sampleMax: inout Float, samplesToProcess: Int, downSampledLength: Int, samplesPerPixel: Int, filter: [Float]) -> [Float] {
		
		var downSampledData = [Float]()
		let sampleLength = sampleBuffer.count / MemoryLayout<Int16>.size
		sampleBuffer.withUnsafeBytes { (samplesRawPointer: UnsafeRawBufferPointer) in
			 let unsafeSamplesBufferPointer = samplesRawPointer.bindMemory(to: Int16.self)
			 let unsafeSamplesPointer = unsafeSamplesBufferPointer.baseAddress!
			 var loudestClipValue: Float = 0.0
			 var quietestClipValue = silenceDbThreshold
			 var zeroDbEquivalent: Float = Float(Int16.max) // maximum amplitude storable in Int16 = 0 Db (loudest)
			 let samplesToProcess = vDSP_Length(sampleLength)

			 var processingBuffer = [Float](repeating: 0.0, count: Int(samplesToProcess))
			 vDSP_vflt16(unsafeSamplesPointer, 1, &processingBuffer, 1, samplesToProcess) // convert 16bit int to float (
			 vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, samplesToProcess) // absolute amplitude value
			 vDSP_vdbcon(processingBuffer, 1, &zeroDbEquivalent, &processingBuffer, 1, samplesToProcess, 1) // convert to DB
			 vDSP_vclip(processingBuffer, 1, &quietestClipValue, &loudestClipValue, &processingBuffer, 1, samplesToProcess)

			 let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
			 let downSampledLength = sampleLength / samplesPerPixel
			 downSampledData = [Float](repeating: 0.0, count: downSampledLength)

			 vDSP_desamp(processingBuffer,
							 vDSP_Stride(samplesPerPixel),
							 filter,
							 &downSampledData,
							 vDSP_Length(downSampledLength),
							 vDSP_Length(samplesPerPixel))
		}

		return downSampledData
	}

	func setup(completion: @escaping (Error?) -> Void) {
		let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])
		guard let track = asset.tracks(withMediaType: .audio).first else {
			self.state = .failedToLoad
			completion(AudioAnalysisError.failedToCreateTrack)
			return
		}
		
		cmDuration = asset.duration
		track.loadValuesAsynchronously(forKeys: ["duration"]) {
			guard
				let formatDescriptions = track.formatDescriptions as? [CMAudioFormatDescription],
				let audioFormatDesc = formatDescriptions.first,
				let formatDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
			else {
					completion(AudioAnalysisError.failedToLoadTrack)
					return
			}
			
			do {
				self.reader = try AVAssetReader(asset: asset)
				self.track = track
				self.numberOfChannels = Int(formatDescription.pointee.mChannelsPerFrame)
				self.sampleRate = CMTimeScale(formatDescription.pointee.mSampleRate)
				self.numberOfSamples = Int((formatDescription.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale)) * self.numberOfChannels

				self.state = .loaded
				completion(nil)
			} catch {
				self.state = .failedToLoad
				completion(AudioAnalysisError.failedToLoadTrack)
			}
		}
	}
}

extension CMTime {
	func percentage(of time: CMTime) -> Double {
		if time.timescale == timescale { return Double(value) / Double(time.value) }
		
		return (Double(value) * Double(timescale)) / (Double(time.value) * Double(time.timescale))
	}
}
