//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct AudioTranscriptTests {
    private static let transcript = AudioTranscript(text: "Hi Bob, I'll be there.",
                                                    words: [.init(endOffset: 2, startTime: 0),
                                                            .init(endOffset: 7, startTime: 0.4),
                                                            // Bob pauses for breath here.
                                                            .init(endOffset: 12, startTime: 1.5),
                                                            .init(endOffset: 15, startTime: 1.8),
                                                            .init(endOffset: 22, startTime: 2)])
    
    @Test
    func countsTheCharactersSpokenSoFar() {
        #expect(Self.transcript.spokenCharacterCount(at: 0) == 2)
        #expect(Self.transcript.spokenCharacterCount(at: 0.4) == 7)
        #expect(Self.transcript.spokenCharacterCount(at: 1.9) == 15)
        #expect(Self.transcript.spokenCharacterCount(at: 2) == 22)
    }
    
    @Test
    func keepsAWordSpokenUntilTheNextOneBegins() {
        #expect(Self.transcript.spokenCharacterCount(at: 1.2) == 7)
        #expect(Self.transcript.spokenCharacterCount(at: 5) == 22)
    }
    
    @Test
    func countsNothingBeforeTheFirstWordIsSpoken() {
        let transcript = AudioTranscript(text: "Hi", words: [.init(endOffset: 2, startTime: 0.5)])
        
        #expect(transcript.spokenCharacterCount(at: 0) == 0)
        #expect(AudioTranscript(text: Self.transcript.text).spokenCharacterCount(at: 1) == 0)
    }
}
