//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import Speech

/// Transcribes audio files with `SpeechAnalyzer`, which runs entirely on device and so needs
/// neither a speech recognition permission nor a network connection once its model is installed.
@available(iOS 26.0, *)
nonisolated struct AudioFileTranscriber: AudioFileTranscriberProtocol {
    func transcribe(fileURL: URL) async -> Result<AudioTranscript, AudioFileTranscriberError> {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            MXLog.error("Speech transcription isn't supported for the current locale.")
            return .failure(.unsupportedLocale)
        }
        
        let preset = SpeechTranscriber.Preset.transcription
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: preset.transcriptionOptions,
                                            reportingOptions: preset.reportingOptions,
                                            attributeOptions: preset.attributeOptions.union([.audioTimeRange]))
        
        do {
            // The model is shared system-wide and only downloaded the first time a locale is used.
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }
            
            let audioFile = try AVAudioFile(forReading: fileURL)
            
            // Results are only delivered whilst the analyzer runs, so collect them before starting it.
            async let attributedTranscript = try transcriber.results.reduce(AttributedString()) { $0 + $1.text }
            
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            
            let transcript = try await AudioTranscript(attributedTranscript)
            guard !transcript.text.isEmpty else {
                MXLog.error("No speech was recognised in the audio file.")
                return .failure(.failedTranscribing)
            }
            return .success(transcript)
        } catch {
            MXLog.error("Failed transcribing the audio file: \(error)")
            return .failure(.failedTranscribing)
        }
    }
}

@available(iOS 26.0, *)
private extension AudioTranscript {
    init(_ attributedTranscript: AttributedString) {
        var text = ""
        var words: [Word] = []
        
        // The transcriber delivers a run per word, each one carrying the time range it was spoken in.
        for run in attributedTranscript.runs {
            var runText = String(attributedTranscript[run.range].characters)
            
            // A run includes the whitespace that separates it from the one before, which would
            // otherwise indent the transcript.
            if text.isEmpty {
                runText = String(runText.drop(while: \.isWhitespace))
            }
            text += runText
            
            if let timeRange = run.audioTimeRange, !runText.isEmpty {
                words.append(Word(endOffset: text.count, startTime: timeRange.start.seconds))
            }
        }
        
        self.init(text: text.trimmingCharacters(in: .whitespacesAndNewlines), words: words)
    }
}
