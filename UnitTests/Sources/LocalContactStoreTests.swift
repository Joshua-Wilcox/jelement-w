// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

@testable import ElementX
import Foundation
import Testing

struct LocalContactStoreTests {
    @Test
    func localFieldsCanBeClearedIndependentlyAfterReload() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "account/Contacts.plist")
        let id = "@contact:test"
        let photo = Data([1, 2, 3])
        try LocalContactStore(file: file).save(name: " Alex ", photo: photo, for: id)
        
        let restored = LocalContactStore(file: file)
        let upstream = UserProfile(userID: id, displayName: "Updated profile", avatarURL: URL(string: "mxc://test/new"))
        #expect(restored.contact(for: id)?.applying(to: upstream).displayName == "Alex")
        #expect(restored.contact(for: id)?.applying(to: upstream).localAvatar == photo)
        #expect(LocalContactStore(file: root.appending(path: "other/Contacts.plist")).contact(for: id) == nil)
        
        try restored.save(name: "", photo: photo, for: id)
        #expect(restored.contact(for: id)?.applying(to: upstream).displayName == upstream.displayName)
        #expect(restored.contact(for: id)?.photo == photo)
        
        try restored.save(name: "Alex", photo: nil, for: id)
        #expect(restored.contact(for: id)?.applying(to: upstream).avatarURL == upstream.avatarURL)
        #expect(restored.contact(for: id)?.name == "Alex")
        
        try restored.save(name: "", photo: nil, for: id)
        #expect(LocalContactStore(file: file).contact(for: id) == nil)
    }
}
