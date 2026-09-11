//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct VoiceMessageTranscriptionServiceTests {
    private static let voiceMessageURL = URL("file:///voice-message.m4a")
    private static let transcript = "Hi Bob, I'll be there at 5pm."
    
    private let voiceMessageMediaManager: VoiceMessageMediaManagerMock
    private let audioFileTranscriber: AudioFileTranscriberMock
    private let service: VoiceMessageTranscriptionService
    private let source: MediaSourceProxy
    
    init() throws {
        voiceMessageMediaManager = VoiceMessageMediaManagerMock()
        voiceMessageMediaManager.loadVoiceMessageFromSourceBodyReturnValue = Self.voiceMessageURL
        
        audioFileTranscriber = AudioFileTranscriberMock()
        audioFileTranscriber.transcribeFileURLReturnValue = .success(Self.transcript)
        
        service = VoiceMessageTranscriptionService(voiceMessageMediaManager: voiceMessageMediaManager,
                                                   audioFileTranscriber: audioFileTranscriber)
        source = try MediaSourceProxy(url: .mockMXCAudio, mimeType: "audio/ogg")
    }
    
    @Test
    func statesAreSharedPerSource() throws {
        let otherSource = try MediaSourceProxy(url: URL("mxc://matrix.org/other-voice-message"), mimeType: "audio/ogg")
        
        #expect(service.transcriptionState(for: source).status == .idle)
        #expect(service.transcriptionState(for: source) === service.transcriptionState(for: source))
        #expect(service.transcriptionState(for: source) !== service.transcriptionState(for: otherSource))
    }
    
    @Test
    func transcribesTheLoadedVoiceMessage() async {
        await service.transcribeVoiceMessage(from: source)
        
        #expect(voiceMessageMediaManager.loadVoiceMessageFromSourceBodyReceivedArguments?.source == source)
        #expect(audioFileTranscriber.transcribeFileURLReceivedFileURL == Self.voiceMessageURL)
        #expect(service.transcriptionState(for: source).status == .completed(transcript: Self.transcript))
    }
    
    @Test
    func reportsAVoiceMessageThatFailedToLoad() async {
        voiceMessageMediaManager.loadVoiceMessageFromSourceBodyThrowableError = VoiceMessageMediaManagerError.missingURL
        
        await service.transcribeVoiceMessage(from: source)
        
        #expect(!audioFileTranscriber.transcribeFileURLCalled)
        #expect(service.transcriptionState(for: source).status == .failed(.failedLoadingVoiceMessage))
    }
    
    @Test
    func reportsAnUnsupportedLanguage() async {
        audioFileTranscriber.transcribeFileURLReturnValue = .failure(.unsupportedLocale)
        
        await service.transcribeVoiceMessage(from: source)
        
        #expect(service.transcriptionState(for: source).status == .failed(.unsupportedLanguage))
    }
    
    @Test
    func reportsAFailedTranscription() async {
        audioFileTranscriber.transcribeFileURLReturnValue = .failure(.failedTranscribing)
        
        await service.transcribeVoiceMessage(from: source)
        
        #expect(service.transcriptionState(for: source).status == .failed(.failedTranscribing))
    }
    
    @Test
    func retriesAfterAFailure() async {
        audioFileTranscriber.transcribeFileURLReturnValue = .failure(.failedTranscribing)
        await service.transcribeVoiceMessage(from: source)
        
        audioFileTranscriber.transcribeFileURLReturnValue = .success(Self.transcript)
        await service.transcribeVoiceMessage(from: source)
        
        #expect(audioFileTranscriber.transcribeFileURLCallsCount == 2)
        #expect(service.transcriptionState(for: source).status == .completed(transcript: Self.transcript))
    }
    
    @Test
    func reusesACompletedTranscript() async {
        await service.transcribeVoiceMessage(from: source)
        await service.transcribeVoiceMessage(from: source)
        
        #expect(voiceMessageMediaManager.loadVoiceMessageFromSourceBodyCallsCount == 1)
        #expect(audioFileTranscriber.transcribeFileURLCallsCount == 1)
        #expect(service.transcriptionState(for: source).status == .completed(transcript: Self.transcript))
    }
    
    @Test
    func joinsATranscriptionThatIsInProgress() async {
        // The task only starts once the direct call suspends, by which point it should find the transcription in flight.
        let duplicateRequest = Task { await service.transcribeVoiceMessage(from: source) }
        await service.transcribeVoiceMessage(from: source)
        await duplicateRequest.value
        
        #expect(voiceMessageMediaManager.loadVoiceMessageFromSourceBodyCallsCount == 1)
        #expect(audioFileTranscriber.transcribeFileURLCallsCount == 1)
        #expect(service.transcriptionState(for: source).status == .completed(transcript: Self.transcript))
    }
    
    @Test
    func reportsProgressThroughTheState() async throws {
        let transcriptionState = service.transcriptionState(for: source)
        let deferred = deferFulfillment(transcriptionState.$status) { $0 == .loading }
        
        let transcription = Task { await service.transcribeVoiceMessage(from: source) }
        try await deferred.fulfill()
        await transcription.value
        
        #expect(transcriptionState.status == .completed(transcript: Self.transcript))
    }
}
