//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AudioFileTranscriberError: Error {
    /// The device can't transcribe the current locale or any equivalent one.
    case unsupportedLocale
    case failedTranscribing
}

/// Transcribes the speech in an audio file on device, in the language of the current locale.
nonisolated protocol AudioFileTranscriberProtocol: Sendable {
    func transcribe(fileURL: URL) async -> Result<String, AudioFileTranscriberError>
}

// sourcery: AutoMockable
extension AudioFileTranscriberProtocol { }
