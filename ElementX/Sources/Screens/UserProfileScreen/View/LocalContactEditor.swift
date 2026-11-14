// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

import Compound
import PhotosUI
import SwiftUI

struct LocalContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var showsError = false
    
    let profile: UserProfile
    let store: LocalContactStore
    let mediaProvider: MediaProviderProtocol?
    
    init(profile: UserProfile, store: LocalContactStore, mediaProvider: MediaProviderProtocol?) {
        self.profile = profile
        self.store = store
        self.mediaProvider = mediaProvider
        let existing = store.contact(for: profile.id)
        _name = State(initialValue: existing?.name ?? "")
        _photo = State(initialValue: existing?.photo)
    }
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    LoadableAvatarImage(url: profile.avatarURL,
                                        name: name.isEmpty ? profile.displayName : name,
                                        contentID: profile.id,
                                        avatarSize: .user(on: .memberDetails),
                                        mediaProvider: mediaProvider,
                                        localAvatar: photo)
                        .frame(maxWidth: .infinity)
                    TextField(UntranslatedL10n.commonLocalContactNameIos, text: $name, prompt: Text(profile.displayName ?? profile.id))
                    if !name.isEmpty {
                        Button(UntranslatedL10n.actionClearLocalContactNameIos) { name = "" }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text(UntranslatedL10n.actionChooseLocalContactPhotoIos)
                        }
                    }
                    if photo != nil {
                        Button(UntranslatedL10n.actionClearLocalContactPhotoIos) { photo = nil }
                    }
                } footer: {
                    Text(UntranslatedL10n.commonLocalContactExplanationIos)
                }
                .disabled(isImporting)
            }
            .compoundList()
            .navigationTitle(UntranslatedL10n.actionEditLocalContactIos)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.actionCancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.actionSave, action: save).disabled(isImporting) }
            }
            .alert(UntranslatedL10n.errorLocalContactIos, isPresented: $showsError) {
                Button(L10n.actionOk, role: .cancel) { }
            }
            .task(id: pickerItem) {
                guard let pickerItem else { return }
                isImporting = true
                defer { isImporting = false }
                guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                      let resized = await LocalContactStore.importPhoto(data) else {
                    if !Task.isCancelled {
                        showsError = true
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                photo = resized
            }
        }
    }
    
    private func save() {
        do {
            try store.save(name: name, photo: photo, for: profile.id)
            dismiss()
        } catch {
            showsError = true
        }
    }
}

struct LocalContactEditor_Previews: PreviewProvider {
    static var previews: some View {
        LocalContactEditor(profile: .init(userID: "@contact:example.org", displayName: "Alex"),
                           store: .init(file: .temporaryDirectory.appending(path: UUID().uuidString)),
                           mediaProvider: nil)
    }
}

struct LocalContactRow: View {
    let profile: UserProfile
    let store: LocalContactStore
    let mediaProvider: MediaProviderProtocol?
    @State private var isEditing = false
    
    var body: some View {
        ListRow(label: .plain(title: UntranslatedL10n.actionEditLocalContactIos),
                kind: .button { isEditing = true })
            .sheet(isPresented: $isEditing) {
                LocalContactEditor(profile: profile, store: store, mediaProvider: mediaProvider)
            }
    }
}

struct RoomLocalContactRow: View {
    let store: LocalContactStore
    let roomID: String
    let ownUserID: String
    let summaries: CurrentValuePublisher<[RoomSummary], Never>
    let mediaProvider: MediaProviderProtocol?
    @State private var profile: UserProfile?
    
    var body: some View {
        Group {
            if let profile {
                Section {
                    LocalContactRow(profile: profile, store: store, mediaProvider: mediaProvider)
                }
            }
        }
        .onReceive(summaries) { rooms in
            profile = rooms.first { $0.id == roomID }?.contact(ownUserID: ownUserID)
        }
    }
}
