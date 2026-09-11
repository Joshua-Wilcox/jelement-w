//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum AudioSegmentMergerError: Error {
    case missingAudioTrack
    case mergeFailed(Error?)
}

/// Joins audio files into a single file, one after another in the order they're given.
nonisolated protocol AudioSegmentMergerProtocol: Sendable {
    func merge(_ segmentURLs: [URL], into destinationURL: URL) async throws
}

// sourcery: AutoMockable
extension AudioSegmentMergerProtocol { }
