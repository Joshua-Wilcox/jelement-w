//
// Copyright 2026 Element Creations Ltd.
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum BeeperRoomPresentation: Equatable {
    case direct(UserProfile)
    case group
}

nonisolated struct BeeperRoomMetadata {
    private static let functionalMembersType = "io.element.functional_members"
    
    // The Swift SDK's classic sync listener exposes room IDs but omits custom state.
    // Fetch just the state needed for chat classification through a separate sync cursor.
    static let syncFilter = """
    {
      "presence":{"types":[]},"account_data":{"types":["m.direct"]},
      "room": {
        "ephemeral":{"types":[]},"account_data":{"types":[]},
        "timeline":{"limit":20,"types":["m.bridge","uk.half-shot.bridge","io.element.functional_members","m.room.member"]},
        "state":{"types":["m.bridge","uk.half-shot.bridge","io.element.functional_members","m.room.member"]}
      }
    }
    """
    
    private var rooms: [String: RoomState] = [:]
    private var directTargets: [String: Set<String>] = [:]
    
    mutating func apply(_ response: Response, ownUserID: String) -> [String: BeeperRoomPresentation] {
        if let direct = response.accountData?.events.last(where: { $0.type == "m.direct" }) {
            directTargets.removeAll(keepingCapacity: true)
            for (userID, roomIDs) in direct.content.direct ?? [:] {
                for roomID in roomIDs {
                    directTargets[roomID, default: []].insert(userID)
                }
            }
        }
        
        for roomID in (response.rooms?.leave ?? [:]).keys {
            rooms.removeValue(forKey: roomID)
        }
        for (roomID, room) in response.rooms?.join ?? [:] {
            for event in (room.state?.events ?? []) + (room.timeline?.events ?? []) {
                guard let key = event.stateKey else { continue }
                switch event.type {
                case "m.bridge", "uk.half-shot.bridge":
                    let bridgeKey = BridgeKey(type: event.type, key: key)
                    rooms[roomID, default: RoomState()].bridges[bridgeKey] = event.content.bridge
                case Self.functionalMembersType where key.isEmpty:
                    rooms[roomID, default: RoomState()].serviceMembers = Set(event.content.serviceMembers ?? [])
                case "m.room.member":
                    rooms[roomID, default: RoomState()].members[key] = event.content.membership == "join"
                        ? UserProfile(userID: key, displayName: event.content.displayName, avatarURL: event.content.avatarURL)
                        : nil
                default:
                    break
                }
            }
        }
        
        return rooms.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.presentation(ownUserID: ownUserID, directTargets: directTargets[entry.key] ?? [])
        }
    }
    
    private struct BridgeKey: Hashable {
        let type: String
        let key: String
    }
    
    private struct RoomState {
        var bridges: [BridgeKey: Bridge] = [:]
        var serviceMembers: Set<String> = []
        var members: [String: UserProfile] = [:]
        
        func presentation(ownUserID: String, directTargets: Set<String>) -> BeeperRoomPresentation? {
            let metadata = Set(bridges.values)
            guard metadata.count == 1, let bridge = metadata.first else { return nil }
            if let type = bridge.roomType, type != "dm" {
                return .group
            }
            let candidates = members.filter { userID, _ in
                userID != ownUserID && userID != bridge.bot && !serviceMembers.contains(userID)
            }
            guard members[ownUserID] != nil, candidates.count == 1, let contact = candidates.values.first,
                  bridge.roomType == "dm" || directTargets == [contact.id] else {
                return nil
            }
            return .direct(contact)
        }
    }
    
    fileprivate struct Bridge: Hashable {
        let bot: String
        let roomType: String?
    }
    
    struct Response: Decodable {
        let nextBatch: String
        let rooms: Rooms?
        let accountData: Events?
        
        enum CodingKeys: String, CodingKey {
            case nextBatch = "next_batch"
            case rooms
            case accountData = "account_data"
        }
    }
    
    struct Rooms: Decodable {
        let join: [String: JoinedRoom]?
        let leave: [String: JoinedRoom]?
    }
    
    struct JoinedRoom: Decodable {
        let state: Events?
        let timeline: Events?
    }
    
    struct Events: Decodable {
        let events: [Event]
    }
    
    struct Event: Decodable {
        let type: String
        let stateKey: String?
        let content: Content
        
        enum CodingKeys: String, CodingKey {
            case type, content
            case stateKey = "state_key"
        }
    }
    
    struct Content: Decodable {
        fileprivate var bridge: Bridge? {
            guard let bot, !bot.isEmpty else { return nil }
            return Bridge(bot: bot, roomType: roomType)
        }
        
        let bot: String?
        let roomType: String?
        let membership: String?
        let displayName: String?
        let avatarURL: URL?
        let serviceMembers: [String]?
        let direct: [String: [String]]?
        
        enum CodingKeys: String, CodingKey {
            case bot = "bridgebot"
            case roomType = "com.beeper.room_type.v2"
            case membership
            case displayName = "displayname"
            case avatarURL = "avatar_url"
            case serviceMembers = "service_members"
        }
        
        init(from decoder: any Decoder) throws {
            let content = try decoder.container(keyedBy: CodingKeys.self)
            bot = try? content.decode(String.self, forKey: .bot)
            roomType = try? content.decode(String.self, forKey: .roomType)
            membership = try? content.decode(String.self, forKey: .membership)
            displayName = try? content.decode(String.self, forKey: .displayName)
            avatarURL = (try? content.decode(URL.self, forKey: .avatarURL)).flatMap { $0.scheme == "mxc" ? $0 : nil }
            serviceMembers = try? content.decode([String].self, forKey: .serviceMembers)
            direct = try? decoder.singleValueContainer().decode([String: [String]].self)
        }
    }
}
