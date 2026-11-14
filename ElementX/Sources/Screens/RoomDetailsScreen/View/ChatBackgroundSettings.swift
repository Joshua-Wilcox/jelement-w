// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

import Compound
import PhotosUI
import SwiftUI

struct ChatBackgroundSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ChatBackground
    @State private var photo: PhotosPickerItem?
    @State private var isImporting = false
    @State private var showsError = false
    
    let store: ChatBackgroundStore
    let roomID: String
    
    init(store: ChatBackgroundStore, roomID: String) {
        self.store = store
        self.roomID = roomID
        _selection = State(initialValue: store.background(for: roomID))
    }
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ChatBackgroundSurface(background: selection)
                        .frame(height: 152)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                Section {
                    choice(UntranslatedL10n.commonChatBackgroundDefaultIos, .standard)
                    choice(UntranslatedL10n.commonChatBackgroundBlueIos, .colour(.blue))
                    choice(UntranslatedL10n.commonChatBackgroundGreenIos, .colour(.green))
                    choice(UntranslatedL10n.commonChatBackgroundPurpleIos, .colour(.purple))
                    PhotosPicker(selection: $photo, matching: .images) {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text(UntranslatedL10n.actionChooseChatBackgroundPhotoIos)
                        }
                    }
                }
                .disabled(isImporting)
            }
            .compoundList()
            .navigationTitle(UntranslatedL10n.screenRoomDetailsChatBackgroundIos)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.actionCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionSave, action: save)
                        .disabled(isImporting)
                }
            }
            .alert(UntranslatedL10n.errorChatBackgroundIos, isPresented: $showsError) {
                Button(L10n.actionOk, role: .cancel) { }
            }
            .task(id: photo) {
                guard let photo else { return }
                isImporting = true
                defer { isImporting = false }
                guard let original = try? await photo.loadTransferable(type: Data.self),
                      let resized = await ChatBackgroundPhoto.downsample(original) else {
                    if !Task.isCancelled {
                        showsError = true
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                selection = .photo(resized)
            }
        }
    }
    
    private func choice(_ title: String, _ background: ChatBackground) -> some View {
        ListRow(label: .plain(title: title), kind: .button {
            selection = background
        })
        .accessibilityAddTraits(selection == background ? .isSelected : [])
    }
    
    private func save() {
        do {
            try store.save(selection, for: roomID)
            dismiss()
        } catch {
            showsError = true
        }
    }
}

struct ChatBackgroundSurface: View {
    let background: ChatBackground
    
    var body: some View {
        Color.compound.bgCanvasDefault
            .overlay {
                switch background {
                case .standard:
                    EmptyView()
                case .colour(let palette):
                    palette.tint.opacity(0.17)
                case .photo(let data):
                    if let image = UIImage(data: data) {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                        .overlay(Color.compound.bgCanvasDefault.opacity(0.48))
                    }
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct ChatBackgroundSettings_Previews: PreviewProvider {
    static var previews: some View {
        ChatBackgroundSettings(store: .init(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
                               roomID: "!room:example.org")
    }
}
