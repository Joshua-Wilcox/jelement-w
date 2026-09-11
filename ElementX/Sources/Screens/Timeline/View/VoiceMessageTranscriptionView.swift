//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The transcription of a voice message shown under its playback controls: a button to start
/// transcribing, the progress whilst it runs, the transcript itself or an error that can be retried.
struct VoiceMessageTranscriptionView: View {
    @ObservedObject var transcriptionState: VoiceMessageTranscriptionState
    /// Not observed here so that the progress of the playback, which is published many times a
    /// second, only updates the transcript itself.
    let playerState: AudioPlayerState
    let onTranscribe: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch transcriptionState.status {
            case .idle:
                transcribeButton(title: UntranslatedL10n.actionTranscribeIos)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(UntranslatedL10n.commonTranscribingIos)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                .accessibilityElement(children: .combine)
            case .completed(let transcript):
                VoiceMessageTranscriptView(playerState: playerState, transcript: transcript)
            case .failed(let error):
                Text(message(for: error))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textCriticalPrimary)
                
                // Retrying can't help when the language isn't supported.
                if error != .unsupportedLanguage {
                    transcribeButton(title: L10n.actionRetry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: transcriptionState.status)
    }
    
    private func transcribeButton(title: String) -> some View {
        Button(title, action: onTranscribe)
            .buttonStyle(.compound(.textLink, size: .small))
    }
    
    private func message(for error: VoiceMessageTranscriptionError) -> String {
        switch error {
        case .unsupportedLanguage:
            UntranslatedL10n.errorVoiceMessageTranscriptionUnsupportedLanguageIos
        case .failedLoadingVoiceMessage, .failedTranscribing:
            UntranslatedL10n.errorVoiceMessageTranscriptionFailedIos
        }
    }
}

/// Follows the playback of the message to work out how much of its transcript has been spoken.
private struct VoiceMessageTranscriptView: View {
    @ObservedObject var playerState: AudioPlayerState
    let transcript: AudioTranscript
    
    /// The whole transcript is shown as spoken until playback begins, and whenever the words
    /// weren't timed, so that it can simply be read.
    private var spokenCharacterCount: Int {
        guard !transcript.words.isEmpty, playerState.duration > 0,
              playerState.playbackState == .playing || playerState.showProgressIndicator else {
            return transcript.text.count
        }
        return transcript.spokenCharacterCount(at: playerState.progress * playerState.duration)
    }
    
    var body: some View {
        VoiceMessageTranscriptText(text: transcript.text, spokenCharacterCount: spokenCharacterCount)
            // Redraws the transcript as each word is reached rather than on every frame of playback.
            .equatable()
    }
}

/// A transcript with the words that are still to be spoken dimmed.
private struct VoiceMessageTranscriptText: View, Equatable {
    let text: String
    let spokenCharacterCount: Int
    
    private var attributedText: AttributedString {
        let spokenEnd = text.index(text.startIndex, offsetBy: min(spokenCharacterCount, text.count))
        
        var spoken = AttributedString(text[..<spokenEnd])
        spoken.foregroundColor = .compound.textPrimary
        var unspoken = AttributedString(text[spokenEnd...])
        unspoken.foregroundColor = .compound.textSecondary
        
        return spoken + unspoken
    }
    
    var body: some View {
        Text(attributedText)
            .font(.compound.bodyLG)
    }
}

nonisolated extension AudioTranscript {
    static let mockTranscript = {
        let spokenWords = [("Hi", 0.0), ("Bob,", 0.4), ("I'll", 1.0), ("be", 1.3), ("there", 1.5), ("at", 1.9),
                           ("5pm.", 2.1), ("Could", 3.2), ("you", 3.5), ("bring", 3.7), ("the", 4.1),
                           ("slides", 4.3), ("for", 4.8), ("tomorrow's", 5.0), ("meeting?", 5.7)]
        
        var text = ""
        var words: [Word] = []
        for (word, startTime) in spokenWords {
            text += text.isEmpty ? word : " \(word)"
            words.append(Word(endOffset: text.count, startTime: startTime))
        }
        
        return AudioTranscript(text: text, words: words)
    }()
}

// MARK: - Previews

struct VoiceMessageTranscriptionView_Previews: PreviewProvider, TestablePreview {
    static let transcriptionStates: [VoiceMessageTranscriptionState] = [
        .init(),
        .init(status: .loading),
        .init(status: .completed(transcript: .mockTranscript)),
        .init(status: .failed(.unsupportedLanguage)),
        .init(status: .failed(.failedTranscribing))
    ]
    
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(transcriptionStates.indices, id: \.self) { index in
                view(transcriptionState: transcriptionStates[index], playerState: playerState())
            }
        }
        .frame(width: 260)
        .padding()
        
        // Midway through playback, where the words still to be spoken are dimmed.
        view(transcriptionState: .init(status: .completed(transcript: .mockTranscript)),
             playerState: playerState(progress: 0.4))
            .frame(width: 260)
            .padding()
            .previewDisplayName("Playback")
    }
    
    static func view(transcriptionState: VoiceMessageTranscriptionState, playerState: AudioPlayerState) -> some View {
        VoiceMessageTranscriptionView(transcriptionState: transcriptionState,
                                      playerState: playerState) { }
    }
    
    static func playerState(progress: Double = 0) -> AudioPlayerState {
        AudioPlayerState(id: .timelineItemIdentifier(.randomEvent),
                         title: L10n.commonVoiceMessage,
                         duration: 10,
                         progress: progress)
    }
}
