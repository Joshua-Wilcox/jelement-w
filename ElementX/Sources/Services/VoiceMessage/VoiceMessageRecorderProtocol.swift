//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

enum VoiceMessageRecorderError: Error {
    case missingRecordingFile
    case previewNotAvailable
    case audioRecorderError(AudioRecorderError)
    case waveformAnalysisError
    case failedMergingSegments
    case failedSendingVoiceMessage
}

enum VoiceMessageRecorderAction {
    case didStartRecording(audioRecorder: AudioRecorderProtocol)
    case didStopRecording(previewState: AudioPlayerState, url: URL)
    case didFailWithError(error: VoiceMessageRecorderError)
}

protocol VoiceMessageRecorderProtocol {
    var previewAudioPlayerState: AudioPlayerState? { get }
    var isRecording: Bool { get }
    var recordingURL: URL? { get }
    
    var actions: AnyPublisher<VoiceMessageRecorderAction, Never> { get }
    
    func startRecording() async
    /// Stops recording, keeping what has been recorded so far so that it can be
    /// played back, resumed or sent.
    func stopRecording() async
    /// Records a new segment of a stopped recording, appending it to the previous ones.
    func resumeRecording() async
    func cancelRecording() async
    func startPlayback() async -> Result<Void, VoiceMessageRecorderError>
    func pausePlayback()
    func stopPlayback() async
    func seekPlayback(to progress: Double) async
    func deleteRecording() async
    
    func sendVoiceMessage(timelineController: TimelineControllerProtocol,
                          audioConverter: AudioConverterProtocol) async -> Result<Void, VoiceMessageRecorderError>
}

// sourcery: AutoMockable
extension VoiceMessageRecorderProtocol { }
