//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

class VoiceMessageTranscriptionService: VoiceMessageTranscriptionServiceProtocol {
    private let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    private let audioFileTranscriber: AudioFileTranscriberProtocol
    
    private var transcriptionStates: [MediaSourceProxy: VoiceMessageTranscriptionState] = [:]
    private var transcriptionTasks: [MediaSourceProxy: Task<Void, Never>] = [:]
    
    init(voiceMessageMediaManager: VoiceMessageMediaManagerProtocol, audioFileTranscriber: AudioFileTranscriberProtocol) {
        self.voiceMessageMediaManager = voiceMessageMediaManager
        self.audioFileTranscriber = audioFileTranscriber
    }
    
    deinit {
        for task in transcriptionTasks.values {
            task.cancel()
        }
    }
    
    func transcriptionState(for source: MediaSourceProxy) -> VoiceMessageTranscriptionState {
        if let transcriptionState = transcriptionStates[source] {
            return transcriptionState
        }
        
        let transcriptionState = VoiceMessageTranscriptionState()
        transcriptionStates[source] = transcriptionState
        return transcriptionState
    }
    
    func transcribeVoiceMessage(from source: MediaSourceProxy) async {
        if let ongoingTask = transcriptionTasks[source] {
            await ongoingTask.value
            return
        }
        
        let transcriptionState = transcriptionState(for: source)
        if case .completed = transcriptionState.status {
            return
        }
        
        transcriptionState.status = .loading
        
        // Only hold `self` weakly whilst transcribing so that tearing down the session cancels the work.
        let task = Task { [weak self, voiceMessageMediaManager, audioFileTranscriber] in
            let status = await Self.transcriptionStatus(for: source,
                                                        voiceMessageMediaManager: voiceMessageMediaManager,
                                                        audioFileTranscriber: audioFileTranscriber)
            guard let self else { return }
            transcriptionTasks[source] = nil
            transcriptionState.status = status
        }
        transcriptionTasks[source] = task
        
        await task.value
    }
    
    // MARK: - Private
    
    private static func transcriptionStatus(for source: MediaSourceProxy,
                                            voiceMessageMediaManager: VoiceMessageMediaManagerProtocol,
                                            audioFileTranscriber: AudioFileTranscriberProtocol) async -> VoiceMessageTranscriptionStatus {
        let fileURL: URL
        do {
            fileURL = try await voiceMessageMediaManager.loadVoiceMessageFromSource(source, body: nil)
        } catch {
            MXLog.error("Failed loading the voice message to transcribe: \(error)")
            return .failed(.failedLoadingVoiceMessage)
        }
        
        switch await audioFileTranscriber.transcribe(fileURL: fileURL) {
        case .success(let transcript):
            return .completed(transcript: transcript)
        case .failure(.unsupportedLocale):
            return .failed(.unsupportedLanguage)
        case .failure(.failedTranscribing):
            return .failed(.failedTranscribing)
        }
    }
}
