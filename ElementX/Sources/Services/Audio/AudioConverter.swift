//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Foundation
import SwiftOGG

enum AudioConverterError: Error {
    case conversionFailed(Error?)
}

enum AudioConverterPreferredFileExtension: String {
    case mpeg4aac = "m4a"
    case ogg
}

nonisolated struct AudioConverter: AudioConverterProtocol {
    func convertToOpusOgg(sourceURL: URL, destinationURL: URL) throws {
        do {
            let opusSourceURL = try urlPreparedForOpusEncoding(from: sourceURL)
            defer {
                if opusSourceURL != sourceURL {
                    try? FileManager.default.removeItem(at: opusSourceURL)
                }
            }
            
            try OGGConverter.convertM4aFileToOpusOGG(src: opusSourceURL, dest: destinationURL)
        } catch {
            MXLog.error("failed to convert to OpusOgg: \(error)")
            throw AudioConverterError.conversionFailed(error)
        }
    }
    
    func convertToMPEG4AAC(sourceURL: URL, destinationURL: URL) throws {
        do {
            try OGGConverter.convertOpusOGGToM4aFile(src: sourceURL, dest: destinationURL)
        } catch {
            MXLog.error("failed to convert to MPEG4AAC: \(error)")
            throw AudioConverterError.conversionFailed(error)
        }
    }
    
    /// The OGG encoder crashes unless the file is 48 kHz, so resample anything that isn't.
    private func urlPreparedForOpusEncoding(from sourceURL: URL) throws -> URL {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        if sourceFile.fileFormat.sampleRate == AudioSegmentMerger.sampleRate {
            return sourceURL
        }
        
        let resampledURL = URL.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(AudioConverterPreferredFileExtension.mpeg4aac.rawValue)
        try AudioSegmentMerger().write([sourceURL], to: resampledURL)
        return resampledURL
    }
}
