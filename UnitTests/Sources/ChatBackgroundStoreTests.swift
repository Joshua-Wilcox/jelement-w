// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

@testable import ElementX
import Foundation
import Testing

struct ChatBackgroundStoreTests {
    @Test
    func keepsEachRoomAndSessionIndependentAfterReload() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        let store = ChatBackgroundStore(directory: first)
        
        try store.save(.colour(.blue), for: "!one:test")
        try store.save(.colour(.green), for: "!two:test")
        
        let restored = ChatBackgroundStore(directory: first)
        #expect(restored.background(for: "!one:test") == .colour(.blue))
        #expect(restored.background(for: "!two:test") == .colour(.green))
        #expect(ChatBackgroundStore(directory: second).background(for: "!two:test") == .standard)
        
        try restored.save(.standard, for: "!one:test")
        let afterReset = ChatBackgroundStore(directory: first)
        #expect(afterReset.background(for: "!one:test") == .standard)
        #expect(afterReset.background(for: "!two:test") == .colour(.green))
    }
    
    @Test
    func invalidPhotoCannotBeImported() async {
        #expect(await ChatBackgroundPhoto.downsample(Data("invalid".utf8)) == nil)
    }
}
