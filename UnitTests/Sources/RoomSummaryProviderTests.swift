//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
import Testing

@MainActor
final class RoomSummaryProviderTests {
    private let baseFilters: [RoomListEntriesDynamicFilterKind] = [.any(filters: [.all(filters: [.nonSpace, .nonLeft]),
                                                                                  .all(filters: [.space, .invite])]),
                                                                   .deduplicateVersions]
    
    var appSettings: AppSettings!
    var roomList: RoomListSDKMock!
    var dynamicEntriesController: RoomListDynamicEntriesControllerSDKMock!
    var roomSummaryProvider: RoomSummaryProvider!
    
    @Test
    func defaultRustFilters() async {
        // Given a new room provider.
        setup()
        await Task.yield()
        
        // Then it should have the default Rust filters enabled.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 1)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: baseFilters))
        
        // When setting one our user filters.
        roomSummaryProvider.setFilter(.all(filters: [.favourites]))
        await Task.yield()
        
        // Then that filter should be added to the default Rust filters.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 2)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: [.all(filters: [.favourite, .joined])] + baseFilters))
    }
    
    @Test
    func lowPriorityRustFilters() async {
        // Given a new room provider with the low priority filter enabled.
        setup(isLowPriorityFilterEnabled: true)
        await Task.yield()
        
        // Then the default Rust filters should include the non-low priority filter,
        // so that low priority rooms are hidden from the top of the room list.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 1)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: baseFilters + [.nonLowPriority]))
        
        // When setting the low priority filter.
        roomSummaryProvider.setFilter(.all(filters: [.lowPriority]))
        await Task.yield()
        
        // Then the non-low priority filter should be replaced with the low priority filter.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 2)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: [.all(filters: [.lowPriority, .joined])] + baseFilters))
        
        // When setting another one of our filters.
        roomSummaryProvider.setFilter(.all(filters: [.rooms]))
        await Task.yield()
        
        // Then the filter should be combined with the non-low priority filter.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 3)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: [.all(filters: [.category(expect: .group), .joined])] + baseFilters + [.nonLowPriority]))
    }
    
    @Test
    func roomIdentifierFilters() async {
        setup()
        await Task.yield()
        
        // Then it should have the default Rust filters enabled.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 1)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: baseFilters))
        
        // When setting one our user filters.
        roomSummaryProvider.setFilter(.rooms(roomsIDs: ["SomeRoom"], filters: [.favourites]))
        await Task.yield()
        
        // Then that filter should be added to the default Rust filters.
        #expect(dynamicEntriesController.setFilterKindCallsCount == 2)
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: [.all(filters: [.favourite, .joined])] + baseFilters + [.identifiers(identifiers: ["SomeRoom"])]))
    }
    
    @Test
    func beeperMetadataDistinguishesDirectChatsFromGroups() throws {
        var metadata = BeeperRoomMetadata()
        let result = try apply("""
        {
          "next_batch": "1",
          "account_data": {"events": [{"type": "m.direct", "content": {"@contact:test": ["!group:test", "!legacy:test", "!native:test"]}}]},
          "rooms": {"join": {
            "!dm:test": {"state": {"events": [
              {"type": "m.bridge", "state_key": "", "content": {"bridgebot": "@bot:test", "com.beeper.room_type.v2": "dm"}},
              {"type": "m.room.member", "state_key": "@me:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@bot:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@contact:test", "content": {"membership": "join", "displayname": "Contact", "avatar_url": "mxc://test/avatar"}}
            ]}},
            "!group:test": {"state": {"events": [
              {"type": "m.bridge", "state_key": "", "content": {"bridgebot": "@bot:test", "com.beeper.room_type.v2": "group_dm"}},
              {"type": "m.room.member", "state_key": "@me:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@bot:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@contact:test", "content": {"membership": "join"}}
            ]}},
            "!legacy:test": {"state": {"events": [
              {"type": "uk.half-shot.bridge", "state_key": "", "content": {"bridgebot": "@bot:test", "com.beeper.room_type": "dm"}},
              {"type": "io.element.functional_members", "state_key": "", "content": {"service_members": ["@helper:test"]}},
              {"type": "m.room.member", "state_key": "@me:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@contact:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@helper:test", "content": {"membership": "join"}}
            ]}},
            "!unknown:test": {"state": {"events": [
              {"type": "m.bridge", "state_key": "", "content": {"bridgebot": "@bot:test", "com.beeper.room_type": "dm"}},
              {"type": "m.room.member", "state_key": "@me:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@contact:test", "content": {"membership": "join"}}
            ]}},
            "!native:test": {"state": {"events": [
              {"type": "m.room.member", "state_key": "@me:test", "content": {"membership": "join"}},
              {"type": "m.room.member", "state_key": "@contact:test", "content": {"membership": "join"}}
            ]}}
          }}
        }
        """, to: &metadata)
        
        #expect(result["!dm:test"] == .direct(.init(userID: "@contact:test", displayName: "Contact", avatarURL: URL(string: "mxc://test/avatar"))))
        #expect(result["!group:test"] == .group)
        #expect(result["!legacy:test"] == .direct(.init(userID: "@contact:test")))
        #expect(result["!unknown:test"] == nil)
        #expect(result["!native:test"] == nil)
        
        let updated = try apply("""
        {
          "next_batch": "2",
          "rooms": {
            "join": {"!dm:test": {"timeline": {"events": [
              {"type": "m.room.member", "state_key": "@second:test", "content": {"membership": "join"}}
            ]}}},
            "leave": {"!legacy:test": {}}
          }
        }
        """, to: &metadata)
        
        #expect(updated["!dm:test"] == nil)
        #expect(updated["!legacy:test"] == nil)
        #expect(updated["!group:test"] == .group)
    }
    
    @Test
    func beeperFiltersShareTheChatsPresentation() async throws {
        setup(usesBeeperRoomPresentation: true)
        roomSummaryProvider.setFilter(.all(filters: [.people]))
        #expect(dynamicEntriesController.setFilterKindReceivedInvocations.last == .all(filters: [.joined] + baseFilters))
        
        let direct = room(id: "!dm:test")
        let group = room(id: "!group:test")
        let native = room(id: "!native:test", isDM: true)
        
        let contact = UserProfile(userID: "@contact:test", displayName: "Contact")
        roomSummaryProvider.setBeeperPresentations(["!dm:test": .direct(contact), "!group:test": .group])
        let populated = deferFulfillment(roomSummaryProvider.roomListPublisher) { $0.count == 2 }
        roomList.entriesWithDynamicAdaptersPageSizeListenerReceivedArguments?.listener.onUpdate(roomEntriesUpdate: [.reset(values: [direct, group, native])])
        try await populated.fulfill()
        let rooms = roomSummaryProvider.roomListPublisher.value
        #expect(rooms.map(\.id) == ["!dm:test", "!native:test"])
        #expect(rooms.first?.name == "Contact")
        #expect(rooms.first?.heroes == [contact])
        
        roomSummaryProvider.setFilter(.all(filters: [.rooms]))
        #expect(roomSummaryProvider.roomListPublisher.value.map(\.id) == ["!group:test"])
    }
    
    // MARK: - Helpers
    
    private func apply(_ json: String, to metadata: inout BeeperRoomMetadata) throws -> [String: BeeperRoomPresentation] {
        let response = try JSONDecoder().decode(BeeperRoomMetadata.Response.self, from: Data(json.utf8))
        return metadata.apply(response, ownUserID: "@me:test")
    }
    
    private func room(id: String, isDM: Bool = false) -> RoomSDKMock {
        let room = RoomSDKMock()
        room.idReturnValue = id
        room.latestEventReturnValue = .some(.none)
        room.roomInfoReturnValue = .init(id: id,
                                         encryptionState: .notEncrypted,
                                         creators: nil,
                                         displayName: id,
                                         rawName: nil,
                                         topic: nil,
                                         avatarUrl: nil,
                                         isDirect: isDM,
                                         isDm: isDM,
                                         isPublic: false,
                                         isSpace: false,
                                         successorRoom: nil,
                                         isFavourite: false,
                                         isLowPriority: false,
                                         canonicalAlias: nil,
                                         alternativeAliases: [],
                                         membership: .joined,
                                         inviter: nil,
                                         heroes: [],
                                         activeMembersCount: 3,
                                         invitedMembersCount: 0,
                                         joinedMembersCount: 3,
                                         activeServiceMembersCount: 0,
                                         serviceMembers: [],
                                         highlightCount: 0,
                                         notificationCount: 0,
                                         cachedUserDefinedNotificationMode: nil,
                                         hasRoomCall: false,
                                         activeRoomCallParticipants: [],
                                         activeRoomCallConsensusIntent: .none,
                                         isMarkedUnread: false,
                                         numUnreadMessages: 0,
                                         numUnreadNotifications: 0,
                                         numUnreadMentions: 0,
                                         fullyReadEventId: nil,
                                         pinnedEventIds: [],
                                         joinRule: nil,
                                         historyVisibility: .joined,
                                         powerLevels: nil,
                                         roomVersion: nil,
                                         privilegedCreatorsRole: false)
        return room
    }
    
    private func setup(isLowPriorityFilterEnabled: Bool = false, usesBeeperRoomPresentation: Bool = false) {
        appSettings = AppSettings.volatile()
        appSettings.lowPriorityFilterEnabled = isLowPriorityFilterEnabled
        
        let stateEventStringBuilder = RoomStateEventStringBuilder(userID: "@me:matrix.org")
        let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
        let eventStringBuilder = RoomEventStringBuilder(stateEventStringBuilder: stateEventStringBuilder,
                                                        messageEventStringBuilder: RoomMessageEventStringBuilder(attributedStringBuilder: attributedStringBuilder,
                                                                                                                 style: .senderPrefixed),
                                                        shouldPrefixSenderName: true)
        
        roomSummaryProvider = RoomSummaryProvider(roomListService: RoomListServiceSDKMock(),
                                                  eventStringBuilder: eventStringBuilder,
                                                  name: "Test",
                                                  notificationSettings: NotificationSettingsProxyMock(with: .init()),
                                                  appSettings: appSettings,
                                                  usesBeeperRoomPresentation: usesBeeperRoomPresentation)
        
        dynamicEntriesController = RoomListDynamicEntriesControllerSDKMock()
        dynamicEntriesController.setFilterKindReturnValue = true
        let dynamicAdaptersResult = RoomListEntriesWithDynamicAdaptersResultSDKMock()
        dynamicAdaptersResult.controllerReturnValue = dynamicEntriesController
        roomList = RoomListSDKMock()
        roomList.entriesWithDynamicAdaptersPageSizeListenerReturnValue = dynamicAdaptersResult
        roomList.loadingStateListenerReturnValue = .some(.init(state: .notLoaded, stateStream: TaskHandleSDKMock()))
        roomSummaryProvider.setRoomList(roomList)
    }
}
