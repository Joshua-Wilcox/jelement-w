//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

enum VoiceMessageRecordingButtonMode {
    case record
    case resume
    case pause
}

struct VoiceMessageRecordingButton: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let mode: VoiceMessageRecordingButtonMode
    let action: () -> Void
    
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()
    
    private var recordIconColour: Color {
        guard isEnabled else { return .compound.iconDisabled }
        return Compound.supportsGlass ? .compound.iconPrimary : .compound.iconSecondary
    }
    
    private var accessibilityLabel: String {
        switch mode {
        case .record: L10n.a11yVoiceMessageRecord
        case .resume: UntranslatedL10n.a11yVoiceMessageResumeRecordingIos
        case .pause: UntranslatedL10n.a11yVoiceMessagePauseRecordingIos
        }
    }
    
    var body: some View {
        Button {
            impactFeedbackGenerator.impactOccurred()
            action()
        } label: {
            switch mode {
            case .record, .resume:
                CompoundIcon(Compound.supportsGlass ? \.micOnSolid : \.micOn,
                             size: .medium,
                             relativeTo: .compound.headingLG)
                    .foregroundColor(recordIconColour)
                    .scaledPadding(Compound.supportsGlass ? 10 : 6, relativeTo: .compound.headingLG)
            case .pause:
                CompoundIcon(\.pauseSolid,
                             size: Compound.supportsGlass ? .medium : .small,
                             relativeTo: .compound.headingLG)
                    .foregroundColor(.compound.iconOnSolidPrimary)
                    .scaledPadding(Compound.supportsGlass ? 10 : 8, relativeTo: .compound.headingLG)
                    .background(.compound.bgActionPrimaryRest, in: .circle)
                    .compositingGroup()
            }
        }
        .buttonStyle(VoiceMessageRecordingButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct VoiceMessageRecordingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            if isEnabled {
                configuration.label
                    .snapshotableGlassEffect(.regular.interactive(),
                                             snapshotBackground: .compound.bgSubtleSecondary,
                                             in: .circle)
            } else {
                configuration.label
                    .background(.compound.bgSubtlePrimary, in: .circle)
            }
        } else {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

struct VoiceMessageRecordingButton_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        HStack(spacing: 12) {
            VoiceMessageRecordingButton(mode: .record) { }
                .disabled(true)
            VoiceMessageRecordingButton(mode: .record) { }
            VoiceMessageRecordingButton(mode: .resume) { }
            VoiceMessageRecordingButton(mode: .pause) { }
        }
    }
}
