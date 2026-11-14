// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LocalContactOverride: Codable, Equatable {
    var name: String?
    var photo: Data?
    
    func applying(to profile: UserProfile) -> UserProfile {
        UserProfile(userID: profile.id,
                    displayName: name ?? profile.displayName,
                    avatarURL: profile.avatarURL,
                    status: profile.status,
                    localAvatar: photo)
    }
}

@Observable
final class LocalContactStore {
    private let file: URL
    private var contacts: [String: LocalContactOverride]
    let changes = PassthroughSubject<Void, Never>()
    
    init(file: URL) {
        self.file = file
        contacts = (try? Data(contentsOf: file)).flatMap { try? PropertyListDecoder().decode([String: LocalContactOverride].self, from: $0) } ?? [:]
    }
    
    func contact(for userID: String) -> LocalContactOverride? {
        contacts[userID]
    }
    
    func save(name: String, photo: Data?, for userID: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = contacts
        updated[userID] = name.isEmpty && photo == nil ? nil : .init(name: name.isEmpty ? nil : name, photo: photo)
        try FileManager.default.createDirectoryIfNeeded(at: file.deletingLastPathComponent())
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(updated).write(to: file, options: .atomic)
        contacts = updated
        changes.send()
    }
    
    @concurrent
    static func importPhoto(_ data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        
        let result = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(writer) ? result as Data : nil
    }
}
