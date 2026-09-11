//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

nonisolated struct AudioSegmentMerger: AudioSegmentMergerProtocol {
    /// The rate the recorder writes at. The OGG encoder crashes on anything else.
    static let sampleRate: Double = 48000
    
    private static let channelCount: AVAudioChannelCount = 1
    private static let readFrameCapacity: AVAudioFrameCount = 8192
    
    func merge(_ segmentURLs: [URL], into destinationURL: URL) async throws {
        try write(segmentURLs, to: destinationURL)
    }
    
    /// Concatenates the files into one 48 kHz mono AAC recording.
    func write(_ segmentURLs: [URL], to destinationURL: URL) throws {
        guard !segmentURLs.isEmpty else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                                       AVSampleRateKey: Int(Self.sampleRate),
                                       AVEncoderBitRateKey: 128_000,
                                       AVNumberOfChannelsKey: Int(Self.channelCount),
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        
        try? FileManager.default.removeItem(at: destinationURL)
        let outputFile = try AVAudioFile(forWriting: destinationURL, settings: settings)
        
        for segmentURL in segmentURLs {
            try append(segmentURL, to: outputFile)
        }
    }
    
    // MARK: - Private
    
    private func append(_ segmentURL: URL, to outputFile: AVAudioFile) throws {
        let inputFile = try AVAudioFile(forReading: segmentURL)
        let inputFormat = inputFile.processingFormat
        let outputFormat = outputFile.processingFormat
        
        if inputFormat == outputFormat {
            try copy(inputFile, to: outputFile)
            return
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        try convert(inputFile, to: outputFile, converter: converter)
    }
    
    private func copy(_ inputFile: AVAudioFile, to outputFile: AVAudioFile) throws {
        let format = inputFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.readFrameCapacity) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        while inputFile.framePosition < inputFile.length {
            let framesToRead = min(Self.readFrameCapacity, AVAudioFrameCount(inputFile.length - inputFile.framePosition))
            try inputFile.read(into: buffer, frameCount: framesToRead)
            if buffer.frameLength > 0 {
                try outputFile.write(from: buffer)
            }
        }
    }
    
    private func convert(_ inputFile: AVAudioFile,
                         to outputFile: AVAudioFile,
                         converter: AVAudioConverter) throws {
        let inputFormat = inputFile.processingFormat
        let outputFormat = outputFile.processingFormat
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.readFrameCapacity) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        var inputFinished = false
        while true {
            if !inputFinished {
                let framesToRead = min(Self.readFrameCapacity, AVAudioFrameCount(max(inputFile.length - inputFile.framePosition, 0)))
                if framesToRead == 0 {
                    inputFinished = true
                } else {
                    try inputFile.read(into: inputBuffer, frameCount: framesToRead)
                    if inputBuffer.frameLength == 0 {
                        inputFinished = true
                    }
                }
            }
            
            let outputFrameCapacity = max(AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)), 32)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
                throw AudioSegmentMergerError.mergeFailed(nil)
            }
            
            var conversionError: NSError?
            var suppliedInput = false
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if inputFinished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if suppliedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            if let conversionError {
                throw AudioSegmentMergerError.mergeFailed(conversionError)
            }
            
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            
            switch status {
            case .endOfStream, .error:
                if status == .error {
                    throw AudioSegmentMergerError.mergeFailed(nil)
                }
                return
            case .haveData, .inputRanDry:
                if inputFinished, outputBuffer.frameLength == 0 {
                    return
                }
            @unknown default:
                return
            }
        }
    }
}
