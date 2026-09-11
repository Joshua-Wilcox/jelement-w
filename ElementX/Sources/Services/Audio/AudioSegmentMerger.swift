//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

nonisolated struct AudioSegmentMerger: AudioSegmentMergerProtocol {
    func merge(_ segmentURLs: [URL], into destinationURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        for segmentURL in segmentURLs {
            let segment = AVURLAsset(url: segmentURL)
            guard let segmentTrack = try await segment.loadTracks(withMediaType: .audio).first else {
                throw AudioSegmentMergerError.missingAudioTrack
            }
            
            let duration = try await segment.load(.duration)
            try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                                 of: segmentTrack,
                                                 at: composition.duration)
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioSegmentMergerError.mergeFailed(nil)
        }
        
        // AVAssetExportSession will fail if the output URL already exists.
        try? FileManager.default.removeItem(at: destinationURL)
        
        do {
            try await exportSession.export(to: destinationURL, as: .m4a)
        } catch {
            MXLog.error("Failed merging the audio segments: \(error)")
            throw AudioSegmentMergerError.mergeFailed(error)
        }
    }
}
