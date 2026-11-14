// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.

import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ChatBackground: Codable, Equatable {
    case standard
    case colour(Palette)
    case photo(Data)
    
    enum Palette: String, Codable, CaseIterable {
        case blue, green, purple
        
        var tint: Color {
            switch self {
            case .blue: .blue
            case .green: .green
            case .purple: .purple
            }
        }
    }
}

@Observable
final class ChatBackgroundStore {
    private let directory: URL
    private var backgrounds: [String: ChatBackground] = [:]
    
    init(directory: URL) {
        self.directory = directory
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? PropertyListDecoder().decode(Entry.self, from: data) else { continue }
            backgrounds[entry.roomID] = entry.background
        }
    }
    
    func background(for roomID: String) -> ChatBackground {
        backgrounds[roomID] ?? .standard
    }
    
    func save(_ background: ChatBackground, for roomID: String) throws {
        let filename = SHA256.hash(data: Data(roomID.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appending(path: filename).appendingPathExtension("plist")
        if background == .standard {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            backgrounds.removeValue(forKey: roomID)
        } else {
            try FileManager.default.createDirectoryIfNeeded(at: directory)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(Entry(roomID: roomID, background: background)).write(to: file, options: .atomic)
            backgrounds[roomID] = background
        }
    }
    
    private struct Entry: Codable {
        let roomID: String
        let background: ChatBackground
    }
}

enum ChatBackgroundPhoto {
    @concurrent
    static func downsample(_ data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return nil }
        
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(writer) ? output as Data : nil
    }
}
