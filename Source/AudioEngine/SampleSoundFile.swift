//
//  SampledSoundFile.swift
//  
//
//  Created by Ben Gottlieb on 7/21/20.
//

import Foundation
import AVFoundation
import Accelerate
import SwiftUI

public class SampledSoundFile: ObservableObject {
	public enum SoundFileError: Error { case failedToCreateBuffer, failedToReadBuffer, noAudioTrackFound, invalidAudioTrack, unableToConstructAsset }
	public enum State { case loading, loaded, failedToLoad }
	
	let url: URL
	@Published public var state = State.loading
	@Published public var samples: [CGFloat] = []
	@Published public var maxSample: CGFloat = 0
	

	var track: AVAssetTrack!
	var reader: AVAssetReader!
	var numberOfSamples: Int!
	var numberOfChannels: Int!
	var sampleRate: CMTimeScale!

	public init(url: URL, andLoadSampleCount: Int? = 300) {
		self.url = url
		self.setup() { loaded in
			if loaded, let sampleCount = andLoadSampleCount { self.read(downscaleTo: sampleCount) }
		}
	}
	
	public struct Samples {
		public let max: CGFloat
		public let samples: [CGFloat]
	}
	
	@discardableResult
	public func read(in requestedRange: CountableRange<Int>? = nil, downscaleTo targetSamples: Int) -> Samples? {
		if self.state != .loaded { return nil }
		let range = requestedRange ?? 0..<numberOfSamples
		reader.timeRange = CMTimeRange(start: CMTime(value: Int64(range.lowerBound), timescale: sampleRate),
															duration: CMTime(value: Int64(range.count), timescale: sampleRate))
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

		var sampleMax: CGFloat = 0
		let samplesPerPixel = max(1, numberOfChannels * range.count / targetSamples)
		let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)

		var outputSamples: [CGFloat] = []
		var sampleBuffer = Data()

		reader.startReading()
		defer { reader.cancelReading() }
		while reader.status == .reading {
			guard let readBuffer = readerOutput.copyNextSampleBuffer(), let buffer = CMSampleBufferGetDataBuffer(readBuffer) else { break }
			
			var bufferLength = 0
			var bufferPointer: UnsafeMutablePointer<Int8>?
			
			CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: &bufferLength, totalLengthOut: nil, dataPointerOut: &bufferPointer)
			sampleBuffer.append(UnsafeBufferPointer(start: bufferPointer, count: bufferLength))
			CMSampleBufferInvalidate(readBuffer)
			
			let totalSamples = sampleBuffer.count / MemoryLayout<Int16>.size
			let downSampledLength = totalSamples / samplesPerPixel
			let samplesToProcess = downSampledLength * samplesPerPixel
			
			guard samplesToProcess > 0 else { continue }
			self.processSamples(from: &sampleBuffer, sampleMax: &sampleMax, outputSamples: &outputSamples, samplesToProcess: samplesToProcess, downSampledLength: downSampledLength, samplesPerPixel: samplesPerPixel, filter: filter)
		}
		
		let remainingSamples = sampleBuffer.count / MemoryLayout<UInt16>.size
		if remainingSamples > 0 {
			let filter = [Float](repeating: 1.0 / Float(remainingSamples), count: remainingSamples)
			self.processSamples(from: &sampleBuffer, sampleMax: &sampleMax, outputSamples: &outputSamples, samplesToProcess: remainingSamples, downSampledLength: 1, samplesPerPixel: samplesPerPixel, filter: filter)
		}
		
		self.maxSample = sampleMax
		self.samples = outputSamples
		return Samples(max: sampleMax, samples: outputSamples)
	}
	
	func processSamples(from sampleBuffer: inout Data, sampleMax: inout CGFloat, outputSamples: inout [CGFloat], samplesToProcess: Int, downSampledLength: Int, samplesPerPixel: Int, filter: [Float]) {
		
		sampleBuffer.withUnsafeBytes { bytes in
			guard let samples = bytes.bindMemory(to: Int16.self).baseAddress else { return }
			
			var processingBuffer = [Float](repeating: 0.0, count: samplesToProcess)
			let sampleCount = vDSP_Length(samplesToProcess)
			
			vDSP_vflt16(samples, 1, &processingBuffer, 1, sampleCount)
			vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, sampleCount)
			
			var downSampledData = [Float](repeating: 0.0, count: downSampledLength)
			vDSP_desamp(processingBuffer, vDSP_Stride(samplesPerPixel), filter, &downSampledData, vDSP_Length(downSampledLength), vDSP_Length(samplesPerPixel))
			let downSampledDataCG = downSampledData.map { value -> CGFloat in
				let float = CGFloat(value)
				if float > sampleMax { sampleMax = float }
				return float
			}
			
			sampleBuffer.removeFirst(samplesToProcess * MemoryLayout<Int16>.size)
			
			outputSamples += downSampledDataCG
		}
	}
	
}

extension SampledSoundFile {
	func setup(completion: @escaping (Bool) -> Void) {
		let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])
		guard let track = asset.tracks(withMediaType: .audio).first else {
			self.state = .failedToLoad
			completion(false)
			return
		}
		
		track.loadValuesAsynchronously(forKeys: ["duration"]) {
			guard
				let formatDescriptions = track.formatDescriptions as? [CMAudioFormatDescription],
				let audioFormatDesc = formatDescriptions.first,
				let formatDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
			else {
					self.state = .failedToLoad
					completion(false)
					return
			}
			
			do {
				self.reader = try AVAssetReader(asset: asset)
				self.numberOfSamples = Int((formatDescription.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale))
				self.track = track
				self.numberOfChannels = Int(formatDescription.pointee.mChannelsPerFrame)
				self.sampleRate = CMTimeScale(formatDescription.pointee.mSampleRate)
				
				self.state = .loaded
				completion(true)
			} catch {
				self.state = .failedToLoad
				completion(false)
			}
		}
		
	}
}
