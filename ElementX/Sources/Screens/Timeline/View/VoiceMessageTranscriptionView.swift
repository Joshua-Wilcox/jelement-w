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
                Text(transcript)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
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

// MARK: - Previews

struct VoiceMessageTranscriptionView_Previews: PreviewProvider, TestablePreview {
    static let transcriptionStates: [VoiceMessageTranscriptionState] = [
        .init(),
        .init(status: .loading),
        .init(status: .completed(transcript: "Hi Bob, I'll be there at 5pm. Could you bring the slides for tomorrow's meeting?")),
        .init(status: .failed(.unsupportedLanguage)),
        .init(status: .failed(.failedTranscribing))
    ]
    
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(transcriptionStates.indices, id: \.self) { index in
                VoiceMessageTranscriptionView(transcriptionState: transcriptionStates[index]) { }
            }
        }
        .frame(width: 260)
        .padding()
    }
}
