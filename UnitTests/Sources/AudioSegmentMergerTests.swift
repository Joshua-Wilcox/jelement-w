//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
@testable import ElementX
import Foundation
import Testing

@MainActor
struct AudioSegmentMergerTests {
    @Test
    func mergeWritesAtTheSampleRateTheOGGEncoderNeeds() async throws {
        let firstSegmentURL = try writeSineWave(sampleRate: 44100, duration: 0.2)
        let secondSegmentURL = try writeSineWave(sampleRate: 44100, duration: 0.3)
        defer {
            try? FileManager.default.removeItem(at: firstSegmentURL)
            try? FileManager.default.removeItem(at: secondSegmentURL)
        }
        
        let mergedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: mergedURL) }
        
        try await AudioSegmentMerger().merge([firstSegmentURL, secondSegmentURL], into: mergedURL)
        
        let mergedFile = try AVAudioFile(forReading: mergedURL)
        #expect(mergedFile.fileFormat.sampleRate == AudioSegmentMerger.sampleRate)
        #expect(mergedFile.fileFormat.channelCount == 1)
        #expect(mergedFile.duration > 0.4)
    }
    
    @Test
    func convertToOpusOggSucceedsAfterMergingNon48kHzSegments() async throws {
        let firstSegmentURL = try writeSineWave(sampleRate: 44100, duration: 0.2)
        let secondSegmentURL = try writeSineWave(sampleRate: 44100, duration: 0.2)
        defer {
            try? FileManager.default.removeItem(at: firstSegmentURL)
            try? FileManager.default.removeItem(at: secondSegmentURL)
        }
        
        let mergedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let oggURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ogg")
        defer {
            try? FileManager.default.removeItem(at: mergedURL)
            try? FileManager.default.removeItem(at: oggURL)
        }
        
        try await AudioSegmentMerger().merge([firstSegmentURL, secondSegmentURL], into: mergedURL)
        try AudioConverter().convertToOpusOgg(sourceURL: mergedURL, destinationURL: oggURL)
        
        #expect(FileManager.default.fileExists(atPath: oggURL.path()))
        #expect(try FileManager.default.sizeForItem(at: oggURL) > 0)
    }
    
    // MARK: - Helpers
    
    /// Writes a short sine wave. 44.1 kHz is what `AVAssetExportPresetAppleM4A` typically emits,
    /// which is the format that used to crash the OGG encoder on send.
    private func writeSineWave(sampleRate: Double, duration: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                                       AVSampleRateKey: Int(sampleRate),
                                       AVEncoderBitRateKey: 128_000,
                                       AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        buffer.frameLength = frameCount
        
        let samples = try #require(buffer.floatChannelData?[0])
        let frequency: Float = 440
        for index in 0..<Int(frameCount) {
            samples[index] = sin(2 * .pi * frequency * Float(index) / Float(format.sampleRate)) * 0.5
        }
        
        try file.write(from: buffer)
        return url
    }
}

private extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}
