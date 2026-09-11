//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SwiftUI

struct VoiceMessageRoomTimelineView: View {
    let timelineItem: VoiceMessageRoomTimelineItem
    let playerState: AudioPlayerState
    /// The transcription of the message, `nil` when transcription isn't available.
    var transcriptionState: VoiceMessageTranscriptionState?
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VoiceMessageRoomTimelineContent(timelineItem: timelineItem,
                                            playerState: playerState,
                                            transcriptionState: transcriptionState)
                .frame(maxWidth: 400)
        }
    }
}

struct VoiceMessageRoomTimelineContent: View {
    @Environment(\.timelineContext) private var context
    @State private var resumePlaybackAfterScrubbing = false
    
    let timelineItem: VoiceMessageRoomTimelineItem
    let playerState: AudioPlayerState
    /// The transcription of the message, `nil` when transcription isn't available.
    var transcriptionState: VoiceMessageTranscriptionState?
    
    var body: some View {
        ContentScanningView(contentScannerService: context?.contentScannerService,
                            mediaSource: timelineItem.content.source) {
            // Transcribing downloads the audio, so it must stay inside the safe content.
            VStack(alignment: .leading, spacing: 8) {
                VoiceMessageRoomPlaybackView(playerState: playerState,
                                             onPlayPause: onPlaybackPlayPause,
                                             onSeek: { onPlaybackSeek($0) },
                                             onScrubbing: { onPlaybackScrubbing($0) },
                                             onPlaybackSpeedChange: onPlaybackSpeedChange)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let transcriptionState {
                    VoiceMessageTranscriptionView(transcriptionState: transcriptionState, onTranscribe: onTranscribe)
                        .padding(.leading, 2)
                        .padding(.trailing, 8)
                }
            }
        } scanningContent: {
            VoiceMessageRoomPlaybackView(playerState: playerState,
                                         isScanning: true,
                                         onPlayPause: { },
                                         onSeek: { _ in },
                                         onScrubbing: { _ in },
                                         onPlaybackSpeedChange: { })
                .fixedSize(horizontal: false, vertical: true)
        } unsafeContent: { failure in
            ContentScanningFailureView(failure: failure)
        }
    }
    
    private func onPlaybackPlayPause() {
        context?.send(viewAction: .handleAudioPlayerAction(.playPause(itemID: timelineItem.id)))
    }
    
    private func onPlaybackSpeedChange() {
        context?.send(viewAction: .handleAudioPlayerAction(.changePlaybackSpeed(itemID: timelineItem.id)))
    }
    
    private func onPlaybackSeek(_ progress: Double) {
        context?.send(viewAction: .handleAudioPlayerAction(.seek(itemID: timelineItem.id, progress: progress)))
    }
    
    private func onPlaybackScrubbing(_ dragging: Bool) {
        if dragging {
            if playerState.playbackState == .playing {
                resumePlaybackAfterScrubbing = true
                context?.send(viewAction: .handleAudioPlayerAction(.playPause(itemID: timelineItem.id)))
            }
        } else {
            if resumePlaybackAfterScrubbing {
                context?.send(viewAction: .handleAudioPlayerAction(.playPause(itemID: timelineItem.id)))
                resumePlaybackAfterScrubbing = false
            }
        }
    }
    
    private func onTranscribe() {
        context?.send(viewAction: .transcribeVoiceMessage(itemID: timelineItem.id))
    }
}

struct VoiceMessageRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    static let scanningViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init(scanResult: nil)))
    static let unsafeViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
    static let timelineItemIdentifier = TimelineItemIdentifier.randomEvent
    static let voiceRoomTimelineItem = VoiceMessageRoomTimelineItem(id: timelineItemIdentifier,
                                                                    timestamp: .mock,
                                                                    isOutgoing: false,
                                                                    isEditable: false,
                                                                    canBeRepliedTo: true,
                                                                    sender: .init(id: "Bob"),
                                                                    content: .init(filename: "audio.ogg",
                                                                                   duration: 300,
                                                                                   waveform: EstimatedWaveform.mockWaveform,
                                                                                   source: try? MediaSourceProxy(url: .mockMXCAudio, mimeType: nil),
                                                                                   fileSize: nil,
                                                                                   contentType: nil))
    
    static let playerState = AudioPlayerState(id: .timelineItemIdentifier(timelineItemIdentifier),
                                              title: L10n.commonVoiceMessage,
                                              duration: 10.0,
                                              waveform: EstimatedWaveform.mockWaveform,
                                              progress: 0.4)
    
    static let transcriptionStates: [VoiceMessageTranscriptionState] = [
        .init(),
        .init(status: .loading),
        .init(status: .completed(transcript: "Hi Bob, I'll be there at 5pm. Could you bring the slides for tomorrow's meeting?")),
        .init(status: .failed(.unsupportedLanguage)),
        .init(status: .failed(.failedTranscribing))
    ]
    
    static var previews: some View {
        body.environmentObject(viewModel.context)
        
        VStack(spacing: 20) {
            VoiceMessageRoomTimelineView(timelineItem: voiceRoomTimelineItem, playerState: playerState)
                .environmentObject(scanningViewModel.context)
                .environment(\.timelineContext, scanningViewModel.context)
            
            VoiceMessageRoomTimelineView(timelineItem: voiceRoomTimelineItem, playerState: playerState)
                .environmentObject(unsafeViewModel.context)
                .environment(\.timelineContext, unsafeViewModel.context)
        }
        .fixedSize(horizontal: false, vertical: true)
        .environmentObject(viewModel.context)
        .previewDisplayName("Content Scanner")
        
        VStack(spacing: 20) {
            ForEach(transcriptionStates.indices, id: \.self) { index in
                VoiceMessageRoomTimelineView(timelineItem: voiceRoomTimelineItem,
                                             playerState: playerState,
                                             transcriptionState: transcriptionStates[index])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
        .previewDisplayName("Transcription")
    }
    
    static var body: some View {
        VoiceMessageRoomTimelineView(timelineItem: voiceRoomTimelineItem, playerState: playerState)
            .fixedSize(horizontal: false, vertical: true)
    }
}
