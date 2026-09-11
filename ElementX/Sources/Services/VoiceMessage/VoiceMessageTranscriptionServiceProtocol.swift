//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

enum VoiceMessageTranscriptionError: Error, Equatable {
    /// The device can't transcribe the current language, so retrying won't help.
    case unsupportedLanguage
    case failedLoadingVoiceMessage
    case failedTranscribing
}

enum VoiceMessageTranscriptionStatus: Equatable {
    case idle
    case loading
    case completed(transcript: AudioTranscript)
    case failed(VoiceMessageTranscriptionError)
}

/// The transcription progress of a voice message. Shared by every view of the message so that the
/// transcript survives the timeline rebuilding its items.
final class VoiceMessageTranscriptionState: ObservableObject {
    @Published var status: VoiceMessageTranscriptionStatus
    
    init(status: VoiceMessageTranscriptionStatus = .idle) {
        self.status = status
    }
}

/// Transcribes voice messages on device, keeping one observable state per media source.
protocol VoiceMessageTranscriptionServiceProtocol {
    /// The state of the voice message with the given source, created on first access.
    func transcriptionState(for source: MediaSourceProxy) -> VoiceMessageTranscriptionState
    
    /// Transcribes the voice message with the given source, reporting progress through its state.
    /// Joins a transcription that's already in progress and returns immediately once one has completed.
    func transcribeVoiceMessage(from source: MediaSourceProxy) async
}

// sourcery: AutoMockable
extension VoiceMessageTranscriptionServiceProtocol { }
