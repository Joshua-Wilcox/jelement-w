//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import DSWaveformImage
import Foundation
import MatrixRustSDK

class VoiceMessageRecorder: VoiceMessageRecorderProtocol {
    let audioRecorder: AudioRecorderProtocol
    private let voiceMessageCache: VoiceMessageCacheProtocol
    private let mediaPlayerProvider: MediaPlayerProviderProtocol
    private let audioSegmentMerger: AudioSegmentMergerProtocol
    
    private let actionsSubject: PassthroughSubject<VoiceMessageRecorderAction, Never> = .init()
    var actions: AnyPublisher<VoiceMessageRecorderAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    var isRecording: Bool {
        audioRecorder.isRecording
    }
    
    /// The file containing everything recorded up to the last time the recording was stopped,
    /// which is the merged one when the recording was paused and resumed.
    var recordingURL: URL? {
        recordedSegmentURLs.count > 1 ? mergedRecordingURL : recordedSegmentURLs.first
    }
    
    /// The duration of the whole recording, including the segments recorded before any pauses.
    var recordingDuration: TimeInterval {
        completedSegmentsDuration + (currentSegmentURL != nil ? audioRecorder.currentTime : 0)
    }
    
    private var recordingCancelled = false
    
    /// The segments that have been recorded, in the order they were spoken.
    private var recordedSegmentURLs: [URL] = []
    /// The segment being recorded, which is only set whilst recording.
    private var currentSegmentURL: URL?
    private var completedSegmentsDuration: TimeInterval = 0
    private var mergedRecordingURL: URL?
    private var finalizeRecordingTask: Task<Void, Never>?
    
    private(set) var previewAudioPlayerState: AudioPlayerState?
    private(set) var previewAudioPlayer: AudioPlayerProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    init(audioRecorder: AudioRecorderProtocol = AudioRecorder(),
         mediaPlayerProvider: MediaPlayerProviderProtocol,
         voiceMessageCache: VoiceMessageCacheProtocol = VoiceMessageCache(),
         audioSegmentMerger: AudioSegmentMergerProtocol = AudioSegmentMerger()) {
        self.audioRecorder = audioRecorder
        self.mediaPlayerProvider = mediaPlayerProvider
        self.voiceMessageCache = voiceMessageCache
        self.audioSegmentMerger = audioSegmentMerger
        
        addObservers()
    }
    
    isolated deinit {
        removeObservers()
    }
    
    // MARK: - Recording
    
    func startRecording() async {
        await stopPlayback()
        previewAudioPlayer?.reset()
        previewAudioPlayerState = nil
        deleteRecordedSegments()
        recordingCancelled = false
        
        await recordNewSegment()
    }
    
    func stopRecording() async {
        recordingCancelled = false
        await audioRecorder.stopRecording()
        
        finalizeRecording()
        // The preview needs to be ready when this returns so that the recording can be sent right away.
        await finalizeRecordingTask?.value
    }
    
    func resumeRecording() async {
        await stopPlayback()
        previewAudioPlayer?.reset()
        recordingCancelled = false
        
        await recordNewSegment()
    }
    
    func cancelRecording() async {
        MXLog.info("Cancel recording.")
        recordingCancelled = true
        await audioRecorder.stopRecording()
        await audioRecorder.deleteRecording()
        deleteRecordedSegments()
        previewAudioPlayerState = nil
        previewAudioPlayer?.reset()
    }
    
    func deleteRecording() async {
        MXLog.info("Delete recording.")
        await stopPlayback()
        await audioRecorder.deleteRecording()
        deleteRecordedSegments()
        previewAudioPlayer?.reset()
        previewAudioPlayerState = nil
    }
    
    // MARK: - Preview
    
    func startPlayback() async -> Result<Void, VoiceMessageRecorderError> {
        guard let previewAudioPlayerState, let url = recordingURL else {
            return .failure(.previewNotAvailable)
        }
        
        guard let audioPlayer = previewAudioPlayer else {
            return .failure(.previewNotAvailable)
        }
        
        if !previewAudioPlayerState.isAttached {
            previewAudioPlayerState.attachAudioPlayer(audioPlayer)
        }
        
        if audioPlayer.playbackURL == url {
            audioPlayer.play()
            return .success(())
        }
        
        audioPlayer.load(sourceURL: url, playbackURL: url, autoplay: true)
        return .success(())
    }
    
    func pausePlayback() {
        previewAudioPlayer?.pause()
    }
    
    func stopPlayback() async {
        guard let previewAudioPlayerState else {
            return
        }
        previewAudioPlayerState.detachAudioPlayer()
        previewAudioPlayer?.stop()
    }
    
    func seekPlayback(to progress: Double) async {
        await previewAudioPlayerState?.updateState(progress: progress)
    }
    
    func buildRecordingWaveform() async -> Result<[Float], VoiceMessageRecorderError> {
        guard let url = recordingURL else {
            return .failure(.missingRecordingFile)
        }
        // build the waveform
        var waveformData: [Float] = []
        let analyzer = WaveformAnalyzer()
        do {
            let samples = try await analyzer.samples(fromAudioAt: url, count: 100)
            // linearly normalized to [0, 1] (1 -> -50 dB)
            waveformData = samples.map { max(0, 1 - $0) }
        } catch {
            MXLog.error("Waveform analysis failed. \(error)")
            return .failure(.waveformAnalysisError)
        }
        return .success(waveformData)
    }
    
    func sendVoiceMessage(timelineController: TimelineControllerProtocol,
                          audioConverter: AudioConverterProtocol) async -> Result<Void, VoiceMessageRecorderError> {
        guard let url = recordingURL else {
            return .failure(VoiceMessageRecorderError.missingRecordingFile)
        }
        
        // convert the file
        let sourceFilename = url.deletingPathExtension().lastPathComponent
        let oggFile = URL.temporaryDirectory.appendingPathComponent(sourceFilename).appendingPathExtension("ogg")
        defer {
            // delete the temporary file
            try? FileManager.default.removeItem(at: oggFile)
        }
        
        do {
            try audioConverter.convertToOpusOgg(sourceURL: url, destinationURL: oggFile)
        } catch {
            return .failure(.failedSendingVoiceMessage)
        }
        
        // send it
        let size: UInt64
        do {
            size = try UInt64(FileManager.default.sizeForItem(at: oggFile))
        } catch {
            MXLog.error("Failed to get the recording file size. \(error)")
            return .failure(.failedSendingVoiceMessage)
        }
        let audioInfo = AudioInfo(duration: recordingDuration, size: size, mimetype: "audio/ogg")
        guard case .success(let waveform) = await buildRecordingWaveform() else {
            return .failure(.failedSendingVoiceMessage)
        }
        
        let result = await timelineController.sendVoiceMessage(url: oggFile,
                                                               audioInfo: audioInfo,
                                                               waveform: waveform) { _ in }
        
        if case .failure(let error) = result {
            MXLog.error("Failed to send the voice message. \(error)")
            return .failure(.failedSendingVoiceMessage)
        }
        
        return .success(())
    }
    
    // MARK: - Private
    
    private func recordNewSegment() async {
        finalizeRecordingTask = nil
        
        let segmentURL = segmentURL(at: recordedSegmentURLs.count)
        currentSegmentURL = segmentURL
        await audioRecorder.record(audioFileURL: segmentURL)
    }
    
    /// The file to record a segment into, which must differ from the merged recording's own file.
    private func segmentURL(at index: Int) -> URL {
        let baseURL = voiceMessageCache.urlForRecording
        return baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseURL.deletingPathExtension().lastPathComponent)-\(index)")
            .appendingPathExtension(baseURL.pathExtension)
    }
    
    private func deleteRecordedSegments() {
        for url in recordedSegmentURLs + [currentSegmentURL, mergedRecordingURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        
        recordedSegmentURLs = []
        currentSegmentURL = nil
        mergedRecordingURL = nil
        completedSegmentsDuration = 0
    }
    
    private func addObservers() {
        audioRecorder.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                self.handleAudioRecorderAction(action)
            }
            .store(in: &cancellables)
    }
    
    private func removeObservers() {
        cancellables.removeAll()
    }
    
    private func handleAudioRecorderAction(_ action: AudioRecorderAction) {
        switch action {
        case .didStartRecording:
            MXLog.info("audio recorder did start recording")
            actionsSubject.send(.didStartRecording(audioRecorder: audioRecorder))
        case .didStopRecording, .didFailWithError(error: .interrupted):
            MXLog.info("audio recorder did stop recording")
            finalizeRecording()
        case .didFailWithError(let error):
            MXLog.info("audio recorder did failed with error: \(error)")
            actionsSubject.send(.didFailWithError(error: .audioRecorderError(error)))
        }
    }
    
    /// Closes the segment that has just been recorded and prepares a preview of the whole recording.
    ///
    /// The recording can be stopped by the recorder itself as well as by the user, so this may be
    /// called twice for the same segment, doing nothing the second time around.
    private func finalizeRecording() {
        guard !recordingCancelled, currentSegmentURL != nil else { return }
        currentSegmentURL = nil
        
        if let segmentURL = audioRecorder.audioFileURL, audioRecorder.currentTime > 0 {
            recordedSegmentURLs.append(segmentURL)
            completedSegmentsDuration += audioRecorder.currentTime
        }
        
        finalizeRecordingTask = Task {
            switch await makeRecordingPreview() {
            case .success(let preview):
                mediaPlayerProvider.register(audioPlayerState: preview.state)
                actionsSubject.send(.didStopRecording(previewState: preview.state, url: preview.url))
            case .failure(let error):
                actionsSubject.send(.didFailWithError(error: error))
            }
        }
    }
    
    private func makeRecordingPreview() async -> Result<(state: AudioPlayerState, url: URL), VoiceMessageRecorderError> {
        MXLog.info("finalize audio recording")
        
        // The segments are only merged when the recording was paused, to avoid re-encoding it needlessly.
        if recordedSegmentURLs.count > 1 {
            let mergedURL = voiceMessageCache.urlForRecording
            do {
                try await audioSegmentMerger.merge(recordedSegmentURLs, into: mergedURL)
            } catch {
                MXLog.error("Failed merging the recorded segments. \(error)")
                return .failure(.failedMergingSegments)
            }
            mergedRecordingURL = mergedURL
        }
        
        guard let url = recordingURL, recordingDuration > 0 else {
            return .failure(.previewNotAvailable)
        }
        
        let state = AudioPlayerState(id: .recorderPreview, title: L10n.commonVoiceMessage, duration: recordingDuration, waveform: EstimatedWaveform(data: []))
        previewAudioPlayerState = state
        previewAudioPlayer = mediaPlayerProvider.player
        
        return .success((state, url))
    }
}
