//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct VoiceMessageRecorderTests {
    private var voiceMessageRecorder: VoiceMessageRecorder!
    
    private var audioRecorder: AudioRecorderMock!
    private var audioRecorderActionsSubject: PassthroughSubject<AudioRecorderAction, Never> = .init()
    private var audioRecorderActions: AnyPublisher<AudioRecorderAction, Never> {
        audioRecorderActionsSubject.eraseToAnyPublisher()
    }
    
    private var mediaPlayerProvider: MediaPlayerProviderMock!
    private var audioConverter: AudioConverterMock!
    private var audioSegmentMerger: AudioSegmentMergerMock!
    private var voiceMessageCache: VoiceMessageCacheMock!
    
    private var audioPlayer: AudioPlayerMock!
    private var audioPlayerActionsSubject: PassthroughSubject<AudioPlayerAction, Never> = .init()
    private var audioPlayerActions: AnyPublisher<AudioPlayerAction, Never> {
        audioPlayerActionsSubject.eraseToAnyPublisher()
    }
    
    private let recordingURL = URL("/some/url")
    
    init() async throws {
        audioRecorder = AudioRecorderMock()
        audioRecorder.currentTime = 0
        audioRecorder.averagePowerReturnValue = 0
        audioRecorder.actions = audioRecorderActions
        
        audioPlayer = AudioPlayerMock()
        audioPlayer.actions = audioPlayerActions
        audioPlayer.state = .stopped
        
        mediaPlayerProvider = MediaPlayerProviderMock()
        mediaPlayerProvider.player = audioPlayer
        audioConverter = AudioConverterMock()
        audioSegmentMerger = AudioSegmentMergerMock()
        voiceMessageCache = VoiceMessageCacheMock()
        voiceMessageCache.urlForRecording = FileManager.default.temporaryDirectory.appendingPathComponent("test-voice-message").appendingPathExtension("m4a")
        
        voiceMessageRecorder = VoiceMessageRecorder(audioRecorder: audioRecorder,
                                                    mediaPlayerProvider: mediaPlayerProvider,
                                                    voiceMessageCache: voiceMessageCache,
                                                    audioSegmentMerger: audioSegmentMerger)
    }
    
    /// Records a voice message and stops it, leaving it ready to be played back, resumed or sent.
    private func setRecordingComplete(fileURL: URL? = nil, duration: TimeInterval = 5) async {
        audioRecorder.audioFileURL = fileURL ?? recordingURL
        audioRecorder.currentTime = duration
        
        await voiceMessageRecorder.startRecording()
        await voiceMessageRecorder.stopRecording()
    }
    
    /// Resumes a stopped recording, appending another segment to it before stopping it again.
    private func setResumedRecordingComplete(fileURL: URL, duration: TimeInterval) async {
        await voiceMessageRecorder.resumeRecording()
        
        audioRecorder.audioFileURL = fileURL
        audioRecorder.currentTime = duration
        
        await voiceMessageRecorder.stopRecording()
    }
    
    @Test
    func recorderRecordingURL() async {
        await setRecordingComplete()
        #expect(voiceMessageRecorder.recordingURL == recordingURL)
    }
    
    @Test
    func recorderRecordingDuration() async {
        await setRecordingComplete(duration: 10.3)
        #expect(voiceMessageRecorder.recordingDuration == 10.3)
    }
    
    @Test
    func startRecording() async {
        _ = await voiceMessageRecorder.startRecording()
        #expect(audioRecorder.recordAudioFileURLCalled)
    }
    
    @Test
    func stopRecording() async {
        _ = await voiceMessageRecorder.stopRecording()
        // Internal audio recorder must have been stopped
        #expect(audioRecorder.stopRecordingCalled)
    }
    
    @Test
    func resumeRecording() async {
        await setRecordingComplete()
        
        await voiceMessageRecorder.resumeRecording()
        
        // A new segment must be recorded so that the first one isn't overwritten
        let segmentURLs = audioRecorder.recordAudioFileURLReceivedInvocations
        #expect(segmentURLs.count == 2)
        #expect(segmentURLs.first != segmentURLs.last)
    }
    
    @Test
    func stopRecordingMergesTheSegmentsOfAResumedRecording() async {
        await setRecordingComplete()
        
        let secondSegmentURL = URL("/some/other/url")
        await setResumedRecordingComplete(fileURL: secondSegmentURL, duration: 3)
        
        #expect(audioSegmentMerger.mergeIntoCallsCount == 1)
        #expect(audioSegmentMerger.mergeIntoReceivedArguments?.segmentURLs == [recordingURL, secondSegmentURL])
        #expect(audioSegmentMerger.mergeIntoReceivedArguments?.destinationURL == voiceMessageCache.urlForRecording)
        // The whole recording must be sent, not just its last segment
        #expect(voiceMessageRecorder.recordingURL == voiceMessageCache.urlForRecording)
        #expect(voiceMessageRecorder.recordingDuration == 8)
        #expect(voiceMessageRecorder.previewAudioPlayerState?.duration == 8)
    }
    
    @Test
    func stopRecordingFailsWhenTheSegmentsCantBeMerged() async throws {
        await setRecordingComplete()
        audioSegmentMerger.mergeIntoThrowableError = AudioSegmentMergerError.mergeFailed(nil)
        
        let deferred = deferFulfillment(voiceMessageRecorder.actions) { action in
            switch action {
            case .didFailWithError(.failedMergingSegments):
                return true
            default:
                return false
            }
        }
        await setResumedRecordingComplete(fileURL: URL("/some/other/url"), duration: 3)
        try await deferred.fulfill()
    }
    
    @Test
    func cancelRecording() async {
        await setRecordingComplete()
        
        await voiceMessageRecorder.cancelRecording()
        
        // Internal audio recorder must have been stopped
        #expect(audioRecorder.stopRecordingCalled)
        // The recording audio file must have been deleted
        #expect(audioRecorder.deleteRecordingCalled)
        #expect(voiceMessageRecorder.recordingURL == nil)
        #expect(voiceMessageRecorder.recordingDuration == 0)
    }
    
    @Test
    func deleteRecording() async {
        await setRecordingComplete()
        
        await voiceMessageRecorder.deleteRecording()
        
        // The recording audio file must have been deleted
        #expect(audioRecorder.deleteRecordingCalled)
        #expect(voiceMessageRecorder.recordingURL == nil)
        #expect(voiceMessageRecorder.recordingDuration == 0)
        #expect(voiceMessageRecorder.previewAudioPlayerState == nil)
    }
    
    @Test
    func deleteRecordingRemovesTheMergedFile() async throws {
        await setRecordingComplete()
        await setResumedRecordingComplete(fileURL: URL("/some/other/url"), duration: 3)
        
        // The merger is mocked, so the file it would have written needs creating by hand.
        let mergedURL = voiceMessageCache.urlForRecording
        try Data().write(to: mergedURL)
        
        await voiceMessageRecorder.deleteRecording()
        
        #expect(!FileManager.default.fileExists(atPath: mergedURL.path()))
    }
    
    @Test
    func startPlaybackNoPreview() async {
        guard case .failure(.previewNotAvailable) = await voiceMessageRecorder.startPlayback() else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func startPlayback() async {
        await setRecordingComplete()
        
        guard case .success = await voiceMessageRecorder.startPlayback() else {
            Issue.record("Playback should start")
            return
        }
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == true)
        #expect(audioPlayer.loadSourceURLPlaybackURLAutoplayCalled)
        #expect(audioPlayer.loadSourceURLPlaybackURLAutoplayReceivedArguments?.sourceURL == recordingURL)
        #expect(audioPlayer.loadSourceURLPlaybackURLAutoplayReceivedArguments?.playbackURL == recordingURL)
        #expect(audioPlayer.loadSourceURLPlaybackURLAutoplayReceivedArguments?.autoplay == true)
        #expect(!audioPlayer.playCalled)
    }
    
    @Test
    func pausePlayback() async {
        await setRecordingComplete()
        
        _ = await voiceMessageRecorder.startPlayback()
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == true)
        
        voiceMessageRecorder.pausePlayback()
        #expect(audioPlayer.pauseCalled)
    }
    
    @Test
    func resumePlayback() async {
        await setRecordingComplete()
        audioPlayer.playbackURL = recordingURL
        
        guard case .success = await voiceMessageRecorder.startPlayback() else {
            Issue.record("Playback should start")
            return
        }
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == true)
        // The media must not have been reloaded
        #expect(!audioPlayer.loadSourceURLPlaybackURLAutoplayCalled)
        #expect(audioPlayer.playCalled)
    }
    
    @Test
    func stopPlayback() async {
        await setRecordingComplete()
        
        _ = await voiceMessageRecorder.startPlayback()
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == true)
        
        await voiceMessageRecorder.stopPlayback()
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == false)
        #expect(audioPlayer.stopCalled)
    }
    
    @Test
    func seekPlayback() async {
        await setRecordingComplete()
        
        _ = await voiceMessageRecorder.startPlayback()
        #expect(voiceMessageRecorder.previewAudioPlayerState?.isAttached == true)
        
        await voiceMessageRecorder.seekPlayback(to: 0.4)
        #expect(audioPlayer.seekToReceivedProgress == 0.4)
    }
    
    @Test
    func buildRecordedWaveform() async throws {
        // If there is no recording file, an error is expected
        audioRecorder.audioFileURL = nil
        guard case .failure(.missingRecordingFile) = await voiceMessageRecorder.buildRecordingWaveform() else {
            Issue.record("An error is expected")
            return
        }
        
        let audioFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_audio", withExtension: "mp3"), "Test audio file is missing")
        await setRecordingComplete(fileURL: audioFileURL)
        guard case .success(let data) = await voiceMessageRecorder.buildRecordingWaveform() else {
            Issue.record("A waveform is expected")
            return
        }
        #expect(!data.isEmpty)
    }
    
    @Test
    func sendVoiceMessage_NoRecordingFile() async {
        let timelineController = TimelineControllerMock(.init())
        
        // If there is no recording file, an error is expected
        audioRecorder.audioFileURL = nil
        guard case .failure(.missingRecordingFile) = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController,
                                                                                                 audioConverter: audioConverter) else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func sendVoiceMessage_ConversionError() async {
        await setRecordingComplete()
        // If the converter returns an error
        audioConverter.convertToOpusOggSourceURLDestinationURLThrowableError = AudioConverterError.conversionFailed(nil)
        
        let timelineController = TimelineControllerMock(.init())
        guard case .failure(.failedSendingVoiceMessage) = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController,
                                                                                                      audioConverter: audioConverter) else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func sendVoiceMessage_InvalidFile() async throws {
        let audioFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_voice_message", withExtension: "m4a"), "Test audio file is missing")
        await setRecordingComplete(fileURL: audioFileURL)
        audioConverter.convertToOpusOggSourceURLDestinationURLClosure = { _, destination in
            try? FileManager.default.removeItem(at: destination)
        }
        
        let timelineProxy = TimelineProxyMock()
        let timelineController = TimelineControllerMock(.init(timelineProxy: timelineProxy))
        timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleReturnValue = .failure(.sdkError(SDKError.generic))
        guard case .failure(.failedSendingVoiceMessage) = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController,
                                                                                                      audioConverter: audioConverter) else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func sendVoiceMessage_WaveformAnlyseFailed() async throws {
        let imageFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_image", withExtension: "png"), "Test image file is missing")
        await setRecordingComplete(fileURL: imageFileURL)
        audioConverter.convertToOpusOggSourceURLDestinationURLClosure = { _, destination in
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: imageFileURL, to: destination)
        }
        
        let timelineProxy = TimelineProxyMock()
        let timelineController = TimelineControllerMock(.init(timelineProxy: timelineProxy))
        timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleReturnValue = .failure(.sdkError(SDKError.generic))
        guard case .failure(.failedSendingVoiceMessage) = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController,
                                                                                                      audioConverter: audioConverter) else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func sendVoiceMessage_SendError() async throws {
        let audioFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_voice_message", withExtension: "m4a"), "Test audio file is missing")
        await setRecordingComplete(fileURL: audioFileURL)
        audioConverter.convertToOpusOggSourceURLDestinationURLClosure = { source, destination in
            try? FileManager.default.removeItem(at: destination)
            let internalConverter = AudioConverter()
            try internalConverter.convertToOpusOgg(sourceURL: source, destinationURL: destination)
        }
        
        // If the media upload fails
        let timelineProxy = TimelineProxyMock()
        let timelineController = TimelineControllerMock(.init(timelineProxy: timelineProxy))
        timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleReturnValue = .failure(.sdkError(SDKError.generic))
        guard case .failure(.failedSendingVoiceMessage) = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController,
                                                                                                      audioConverter: audioConverter) else {
            Issue.record("An error is expected")
            return
        }
    }
    
    @Test
    func sendVoiceMessage() async throws {
        let imageFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_voice_message", withExtension: "m4a"), "Test audio file is missing")
        
        let timelineProxy = TimelineProxyMock()
        let timelineController = TimelineControllerMock(.init(timelineProxy: timelineProxy))
        audioRecorder.currentTime = 42
        audioRecorder.audioFileURL = imageFileURL
        _ = await voiceMessageRecorder.startRecording()
        _ = await voiceMessageRecorder.stopRecording()
        
        var convertedFileURL: URL?
        var convertedFileSize: UInt64?
        
        audioConverter.convertToOpusOggSourceURLDestinationURLClosure = { source, destination in
            convertedFileURL = destination
            try? FileManager.default.removeItem(at: destination)
            let internalConverter = AudioConverter()
            try internalConverter.convertToOpusOgg(sourceURL: source, destinationURL: destination)
            convertedFileSize = try? UInt64(FileManager.default.sizeForItem(at: destination))
            // the source URL must be the recorded file
            #expect(source == imageFileURL)
            // check the converted file extension
            #expect(destination.pathExtension == "ogg")
        }
        
        timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleClosure = { url, audioInfo, waveform, _ in
            #expect(url == convertedFileURL)
            #expect(audioInfo.duration == audioRecorder.currentTime)
            #expect(audioInfo.size == convertedFileSize)
            #expect(audioInfo.mimetype == "audio/ogg")
            #expect(!waveform.isEmpty)
            
            return .success(())
        }
        
        guard case .success = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController, audioConverter: audioConverter) else {
            Issue.record("A success is expected")
            return
        }
        
        #expect(audioConverter.convertToOpusOggSourceURLDestinationURLCalled)
        #expect(timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleCalled)
        
        // the converted file must have been deleted
        if let convertedFileURL {
            #expect(!FileManager.default.fileExists(atPath: convertedFileURL.path()))
        } else {
            Issue.record("converted file URL is missing")
        }
    }
    
    @Test
    func sendVoiceMessage_ResumedRecordingUsesTheMergedFile() async throws {
        let audioFileURL = try #require(Bundle(for: UnitTestsAppCoordinator.self).url(forResource: "test_voice_message", withExtension: "m4a"), "Test audio file is missing")
        audioSegmentMerger.mergeIntoClosure = { urls, destination in
            try await AudioSegmentMerger().merge(urls, into: destination)
        }
        
        await setRecordingComplete(fileURL: audioFileURL, duration: 5)
        await setResumedRecordingComplete(fileURL: audioFileURL, duration: 3)
        
        var convertedSourceURL: URL?
        audioConverter.convertToOpusOggSourceURLDestinationURLClosure = { source, destination in
            convertedSourceURL = source
            try? FileManager.default.removeItem(at: destination)
            try AudioConverter().convertToOpusOgg(sourceURL: source, destinationURL: destination)
        }
        
        let timelineProxy = TimelineProxyMock()
        let timelineController = TimelineControllerMock(.init(timelineProxy: timelineProxy))
        timelineProxy.sendVoiceMessageUrlAudioInfoWaveformRequestHandleReturnValue = .success(())
        
        guard case .success = await voiceMessageRecorder.sendVoiceMessage(timelineController: timelineController, audioConverter: audioConverter) else {
            Issue.record("A success is expected")
            return
        }
        
        let sourceURL = try #require(convertedSourceURL)
        #expect(sourceURL == voiceMessageCache.urlForRecording)
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        #expect(sourceFile.fileFormat.sampleRate == AudioSegmentMerger.sampleRate)
    }
    
    @Test
    func audioRecorderActionHandling_didStartRecording() async throws {
        let deferred = deferFulfillment(voiceMessageRecorder.actions) { action in
            switch action {
            case .didStartRecording:
                return true
            default:
                return false
            }
        }
        audioRecorderActionsSubject.send(.didStartRecording)
        try await deferred.fulfill()
    }
    
    @Test
    func audioRecorderActionHandling_didStopRecording() async throws {
        audioRecorder.audioFileURL = recordingURL
        audioRecorder.currentTime = 5
        await voiceMessageRecorder.startRecording()
        
        let deferred = deferFulfillment(voiceMessageRecorder.actions) { action in
            switch action {
            case .didStopRecording(_, let url) where url == recordingURL:
                return true
            default:
                return false
            }
        }
        audioRecorderActionsSubject.send(.didStopRecording)
        try await deferred.fulfill()
    }
    
    @Test
    func audioRecorderActionHandling_didFailed() async throws {
        audioRecorder.audioFileURL = recordingURL
        
        let deferred = deferFulfillment(voiceMessageRecorder.actions) { action in
            switch action {
            case .didFailWithError:
                return true
            default:
                return false
            }
        }
        audioRecorderActionsSubject.send(.didFailWithError(error: .audioEngineFailure))
        try await deferred.fulfill()
    }
}

private enum SDKError: Error {
    case generic
}
