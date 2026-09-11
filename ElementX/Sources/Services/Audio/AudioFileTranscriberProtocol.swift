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

/// The speech recognised in an audio file, timed word by word when the transcriber supports it.
nonisolated struct AudioTranscript: Equatable, Sendable {
    /// A word of the transcript, given as the point of `text` that it reaches and the moment
    /// of the recording in which it began to be spoken.
    struct Word: Equatable, Sendable {
        /// The number of characters of `text` up to and including this word.
        let endOffset: Int
        let startTime: TimeInterval
    }
    
    let text: String
    /// The words in the order they were spoken, or empty when the transcriber didn't time them.
    let words: [Word]
    
    init(text: String, words: [Word] = []) {
        self.text = text
        self.words = words
    }
    
    /// The number of characters of `text` that have been spoken by the given point of the recording.
    func spokenCharacterCount(at playbackTime: TimeInterval) -> Int {
        words.prefix { $0.startTime <= playbackTime }.last?.endOffset ?? 0
    }
}

/// Transcribes the speech in an audio file on device, in the language of the current locale.
nonisolated protocol AudioFileTranscriberProtocol: Sendable {
    func transcribe(fileURL: URL) async -> Result<AudioTranscript, AudioFileTranscriberError>
}

// sourcery: AutoMockable
extension AudioFileTranscriberProtocol { }
