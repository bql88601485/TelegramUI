import Foundation
import Postbox
import SwiftSignalKit
import Display
import AsyncDisplayKit
import TelegramCore

private let historyMessageCount: Int = 200

public enum ChatHistoryListMode: Equatable {
    case bubbles
    case list(search: Bool, reversed: Bool)
    
    public static func ==(lhs: ChatHistoryListMode, rhs: ChatHistoryListMode) -> Bool {
        switch lhs {
            case .bubbles:
                if case .bubbles = rhs {
                    return true
                } else {
                    return false
                }
            case let .list(search, reversed):
                if case .list(search, reversed) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

enum ChatHistoryViewScrollPosition {
    case unread(index: MessageIndex)
    case positionRestoration(index: MessageIndex, relativeOffset: CGFloat)
    case index(index: MessageHistoryAnchorIndex, position: ListViewScrollPosition, directionHint: ListViewScrollToItemDirectionHint, animated: Bool)
}

enum ChatHistoryViewUpdateType {
    case Initial(fadeIn: Bool)
    case Generic(type: ViewUpdateType)
}

public struct ChatHistoryCombinedInitialReadStateData {
    public let unreadCount: Int32
    public let totalState: ChatListTotalUnreadState?
    public let inAppNotificationSettings: InAppNotificationSettings?
    public let notificationSettings: PeerNotificationSettings?
}

public struct ChatHistoryCombinedInitialData {
    let initialData: InitialMessageHistoryData?
    let buttonKeyboardMessage: Message?
    let cachedData: CachedPeerData?
    let cachedDataMessages: [MessageId: Message]?
    let readStateData: [PeerId: ChatHistoryCombinedInitialReadStateData]?
}

enum ChatHistoryViewUpdate {
    case Loading(initialData: ChatHistoryCombinedInitialData?)
    case HistoryView(view: MessageHistoryView, type: ChatHistoryViewUpdateType, scrollPosition: ChatHistoryViewScrollPosition?, originalScrollPosition: ChatHistoryViewScrollPosition?, initialData: ChatHistoryCombinedInitialData)
}

struct ChatHistoryView {
    let originalView: MessageHistoryView
    let filteredEntries: [ChatHistoryEntry]
    let associatedData: ChatMessageItemAssociatedData
}

enum ChatHistoryViewTransitionReason {
    case Initial(fadeIn: Bool)
    case InteractiveChanges
    case HoleChanges(filledHoleDirections: [MessageIndex: HoleFillDirection], removeHoleDirections: [MessageIndex: HoleFillDirection])
    case Reload
}

struct ChatHistoryViewTransitionInsertEntry {
    let index: Int
    let previousIndex: Int?
    let entry: ChatHistoryEntry
    let directionHint: ListViewItemOperationDirectionHint?
}

struct ChatHistoryViewTransitionUpdateEntry {
    let index: Int
    let previousIndex: Int
    let entry: ChatHistoryEntry
    let directionHint: ListViewItemOperationDirectionHint?
}

struct ChatHistoryViewTransition {
    let historyView: ChatHistoryView
    let deleteItems: [ListViewDeleteItem]
    let insertEntries: [ChatHistoryViewTransitionInsertEntry]
    let updateEntries: [ChatHistoryViewTransitionUpdateEntry]
    let options: ListViewDeleteAndInsertOptions
    let scrollToItem: ListViewScrollToItem?
    let stationaryItemRange: (Int, Int)?
    let initialData: InitialMessageHistoryData?
    let keyboardButtonsMessage: Message?
    let cachedData: CachedPeerData?
    let cachedDataMessages: [MessageId: Message]?
    let readStateData: [PeerId: ChatHistoryCombinedInitialReadStateData]?
    let scrolledToIndex: MessageHistoryAnchorIndex?
    let animateIn: Bool
}

struct ChatHistoryListViewTransition {
    let historyView: ChatHistoryView
    let deleteItems: [ListViewDeleteItem]
    let insertItems: [ListViewInsertItem]
    let updateItems: [ListViewUpdateItem]
    let options: ListViewDeleteAndInsertOptions
    let scrollToItem: ListViewScrollToItem?
    let stationaryItemRange: (Int, Int)?
    let initialData: InitialMessageHistoryData?
    let keyboardButtonsMessage: Message?
    let cachedData: CachedPeerData?
    let cachedDataMessages: [MessageId: Message]?
    let readStateData: [PeerId: ChatHistoryCombinedInitialReadStateData]?
    let scrolledToIndex: MessageHistoryAnchorIndex?
    let animateIn: Bool
}

private func maxMessageIndexForEntries(_ entries: [ChatHistoryEntry], indexRange: (Int, Int)) -> (incoming: MessageIndex?, overall: MessageIndex?) {
    var overall: MessageIndex?
    for i in (indexRange.0 ... indexRange.1).reversed() {
        if case let .MessageEntry(message, _, _, _, _, _) = entries[i] {
            if overall == nil {
                overall = MessageIndex(message)
            }
            if message.flags.contains(.Incoming) {
                return (MessageIndex(message), overall)
            }
        } else if case let .MessageGroupEntry(_, messages, _) = entries[i] {
            let index = MessageIndex(messages[messages.count - 1].0)
            if overall == nil {
                overall = index
            }
            if messages[messages.count - 1].0.flags.contains(.Incoming) {
                return (index, overall)
            }
        }
    }
    return (nil, overall)
}

private func mappedInsertEntries(account: Account, chatLocation: ChatLocation, associatedData: ChatMessageItemAssociatedData, controllerInteraction: ChatControllerInteraction, mode: ChatHistoryListMode, entries: [ChatHistoryViewTransitionInsertEntry]) -> [ListViewInsertItem] {
    return entries.map { entry -> ListViewInsertItem in
        switch entry.entry {
            case let .MessageEntry(message, presentationData, read, _, selection, isAdmin):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatMessageItem(presentationData: presentationData, account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, content: .message(message: message, read: read, selection: selection, isAdmin: isAdmin))
                    case let .list(search, _):
                        item = ListMessageItem(theme: presentationData.theme.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, account: account, chatLocation: chatLocation, controllerInteraction: controllerInteraction, message: message, selection: selection, displayHeader: search)
                }
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .MessageGroupEntry(_, messages, presentationData):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatMessageItem(presentationData: presentationData, account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, content: .group(messages: messages))
                    case let .list(search, _):
                        assertionFailure()
                        item = ListMessageItem(theme: presentationData.theme.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, account: account, chatLocation: chatLocation, controllerInteraction: controllerInteraction, message: messages[0].0, selection: .none, displayHeader: search)
                }
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .HoleEntry(_, theme, strings):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatHoleItem(index: entry.entry.index, theme: theme, strings: strings)
                    case .list:
                        item = ListMessageHoleItem()
                }
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .UnreadEntry(_, presentationData):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatUnreadItem(index: entry.entry.index, presentationData: presentationData), directionHint: entry.directionHint)
            case let .ChatInfoEntry(text, presentationData):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatBotInfoItem(text: text, controllerInteraction: controllerInteraction, presentationData: presentationData), directionHint: entry.directionHint)
            case let .EmptyChatInfoEntry(presentationData, tagMask):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatEmptyItem(presentationData: presentationData, tagMask: tagMask), directionHint: entry.directionHint)
            case let .SearchEntry(theme, strings):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatListSearchItem(theme: theme, placeholder: strings.Common_Search, activate: {
                    controllerInteraction.openSearch()
                }), directionHint: entry.directionHint)
        }
    }
}

private func mappedUpdateEntries(account: Account, chatLocation: ChatLocation, associatedData: ChatMessageItemAssociatedData, controllerInteraction: ChatControllerInteraction, mode: ChatHistoryListMode, entries: [ChatHistoryViewTransitionUpdateEntry]) -> [ListViewUpdateItem] {
    return entries.map { entry -> ListViewUpdateItem in
        switch entry.entry {
            case let .MessageEntry(message, presentationData, read, _, selection, isAdmin):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatMessageItem(presentationData: presentationData, account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, content: .message(message: message, read: read, selection: selection, isAdmin: isAdmin))
                    case let .list(search, _):
                        item = ListMessageItem(theme: presentationData.theme.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, account: account, chatLocation: chatLocation, controllerInteraction: controllerInteraction, message: message, selection: selection, displayHeader: search)
                }
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .MessageGroupEntry(_, messages, presentationData):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatMessageItem(presentationData: presentationData, account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, content: .group(messages: messages))
                    case let .list(search, _):
                        assertionFailure()
                        item = ListMessageItem(theme: presentationData.theme.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, account: account, chatLocation: chatLocation, controllerInteraction: controllerInteraction, message: messages[0].0, selection: .none, displayHeader: search)
                }
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .HoleEntry(_, theme, strings):
                let item: ListViewItem
                switch mode {
                    case .bubbles:
                        item = ChatHoleItem(index: entry.entry.index, theme: theme, strings: strings)
                    case .list:
                        item = ListMessageHoleItem()
                }
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: item, directionHint: entry.directionHint)
            case let .UnreadEntry(_, presentationData):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatUnreadItem(index: entry.entry.index, presentationData: presentationData), directionHint: entry.directionHint)
            case let .ChatInfoEntry(text, presentationData):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatBotInfoItem(text: text, controllerInteraction: controllerInteraction, presentationData: presentationData), directionHint: entry.directionHint)
            case let .EmptyChatInfoEntry(presentationData, tagMask):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatEmptyItem(presentationData: presentationData, tagMask: tagMask), directionHint: entry.directionHint)
            case let .SearchEntry(theme, strings):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatListSearchItem(theme: theme, placeholder: strings.Common_Search, activate: {
                    controllerInteraction.openSearch()
                }), directionHint: entry.directionHint)
        }
    }
}

private func mappedChatHistoryViewListTransition(account: Account, chatLocation: ChatLocation, associatedData: ChatMessageItemAssociatedData, controllerInteraction: ChatControllerInteraction, mode: ChatHistoryListMode, transition: ChatHistoryViewTransition) -> ChatHistoryListViewTransition {
    return ChatHistoryListViewTransition(historyView: transition.historyView, deleteItems: transition.deleteItems, insertItems: mappedInsertEntries(account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, mode: mode, entries: transition.insertEntries), updateItems: mappedUpdateEntries(account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, mode: mode, entries: transition.updateEntries), options: transition.options, scrollToItem: transition.scrollToItem, stationaryItemRange: transition.stationaryItemRange, initialData: transition.initialData, keyboardButtonsMessage: transition.keyboardButtonsMessage, cachedData: transition.cachedData, cachedDataMessages: transition.cachedDataMessages, readStateData: transition.readStateData, scrolledToIndex: transition.scrolledToIndex, animateIn: transition.animateIn)
}

private final class ChatHistoryTransactionOpaqueState {
    let historyView: ChatHistoryView
    
    init(historyView: ChatHistoryView) {
        self.historyView = historyView
    }
}

private func extractAssociatedData(chatLocation: ChatLocation, view: MessageHistoryView, automaticDownloadNetworkType: AutomaticDownloadNetworkType) -> ChatMessageItemAssociatedData {
    var automaticMediaDownloadPeerType: AutomaticMediaDownloadPeerType = .channel
    if case let .peer(peerId) = chatLocation {
        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.SecretChat {
            var isContact = false
            for entry in view.additionalData {
                if case let .peerIsContact(_, value) = entry {
                    isContact = value
                    break
                }
            }
            automaticMediaDownloadPeerType = isContact ? .contact : .otherPrivate
        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
            automaticMediaDownloadPeerType = .group
        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
            for entry in view.additionalData {
                if case let .peer(_, value) = entry {
                    if let channel = value as? TelegramChannel, case .group = channel.info {
                        automaticMediaDownloadPeerType = .group
                    }
                    break
                }
            }
        }
    }
    let associatedData = ChatMessageItemAssociatedData(automaticDownloadPeerType: automaticMediaDownloadPeerType, automaticDownloadNetworkType: automaticDownloadNetworkType, isRecentActions: false)
    return associatedData
}

public final class ChatHistoryListNode: ListView, ChatHistoryNode {
    private let account: Account
    private let chatLocation: ChatLocation
    private let messageId: MessageId?
    private let tagMask: MessageTags?
    private let controllerInteraction: ChatControllerInteraction
    private let mode: ChatHistoryListMode
    
    private var historyView: ChatHistoryView?
    
    private let historyDisposable = MetaDisposable()
    private let readHistoryDisposable = MetaDisposable()
    
    private let messageViewQueue = Queue()
    
    private var dequeuedInitialTransitionOnLayout = false
    private var enqueuedHistoryViewTransition: (ChatHistoryListViewTransition, () -> Void)?
    var layoutActionOnViewTransition: ((ChatHistoryListViewTransition) -> (ChatHistoryListViewTransition, ListViewUpdateSizeAndInsets?))?
    
    public let historyState = ValuePromise<ChatHistoryNodeHistoryState>()
    public var currentHistoryState: ChatHistoryNodeHistoryState?
    
    private let _initialData = Promise<ChatHistoryCombinedInitialData?>()
    private var didSetInitialData = false
    public var initialData: Signal<ChatHistoryCombinedInitialData?, NoError> {
        return self._initialData.get()
    }
    
    private let _cachedPeerDataAndMessages = Promise<(CachedPeerData?, [MessageId: Message]?)>()
    public var cachedPeerDataAndMessages: Signal<(CachedPeerData?, [MessageId: Message]?), NoError> {
        return self._cachedPeerDataAndMessages.get()
    }
    
    private var _buttonKeyboardMessage = Promise<Message?>(nil)
    private var currentButtonKeyboardMessage: Message?
    public var buttonKeyboardMessage: Signal<Message?, NoError> {
        return self._buttonKeyboardMessage.get()
    }
    
    private let maxVisibleIncomingMessageIndex = ValuePromise<MessageIndex>(ignoreRepeated: true)
    let canReadHistory = Promise<Bool>()
    private var canReadHistoryValue: Bool = false
    private var canReadHistoryDisposable: Disposable?
    
    private let _chatHistoryLocation = ValuePromise<ChatHistoryLocation>()
    private var chatHistoryLocation: Signal<ChatHistoryLocation, NoError> {
        return self._chatHistoryLocation.get()
    }
    
    private let galleryHiddenMesageAndMediaDisposable = MetaDisposable()
    
    private let messageProcessingManager = ChatMessageThrottledProcessingManager()
    private let messageMentionProcessingManager = ChatMessageThrottledProcessingManager(delay: 0.2)
    
    private var maxVisibleMessageIndexReported: MessageIndex?
    var maxVisibleMessageIndexUpdated: ((MessageIndex) -> Void)?
    
    var scrolledToIndex: ((MessageHistoryAnchorIndex) -> Void)?
    
    private var currentPresentationData: PresentationData
    private var chatPresentationDataPromise: Promise<ChatPresentationData>
    private var presentationDataDisposable: Disposable?
    
    private(set) var isScrollAtBottomPosition = false
    public var isScrollAtBottomPositionUpdated: (() -> Void)?
    
    private var interactiveReadActionDisposable: Disposable?
    
    public var contentPositionChanged: (ListViewVisibleContentOffset) -> Void = { _ in }
    
    public private(set) var loadState: ChatHistoryNodeLoadState?
    private var loadStateUpdated: ((ChatHistoryNodeLoadState, Bool) -> Void)?
    
    private var loadedMessagesFromCachedDataDisposable: Disposable?
    
    public init(account: Account, chatLocation: ChatLocation, tagMask: MessageTags?, messageId: MessageId?, controllerInteraction: ChatControllerInteraction, selectedMessages: Signal<Set<MessageId>?, NoError>, mode: ChatHistoryListMode = .bubbles) {
        self.account = account
        self.chatLocation = chatLocation
        self.messageId = messageId
        self.tagMask = tagMask
        self.controllerInteraction = controllerInteraction
        self.mode = mode
        
        self.currentPresentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
        
        self.chatPresentationDataPromise = Promise(ChatPresentationData(theme: ChatPresentationThemeData(theme: self.currentPresentationData.theme, wallpaper: self.currentPresentationData.chatWallpaper), fontSize: self.currentPresentationData.fontSize, strings: self.currentPresentationData.strings, dateTimeFormat: self.currentPresentationData.dateTimeFormat, disableAnimations: self.currentPresentationData.disableAnimations))
        
        super.init()
        
        self.dynamicBounceEnabled = !self.currentPresentationData.disableAnimations
        
        //self.stackFromBottom = true
        
        //self.debugInfo = true
        
        self.messageProcessingManager.process = { [weak account] messageIds in
            account?.viewTracker.updateViewCountForMessageIds(messageIds: messageIds)
        }
        self.messageMentionProcessingManager.process = { [weak account] messageIds in
            account?.viewTracker.updateMarkMentionsSeenForMessageIds(messageIds: messageIds)
        }
        
        self.preloadPages = false
        switch self.mode {
            case .bubbles:
                self.transform = CATransform3DMakeRotation(CGFloat(Double.pi), 0.0, 0.0, 1.0)
            case .list:
                break
        }
        //self.snapToBottomInsetUntilFirstInteraction = true
        
        let messageViewQueue = self.messageViewQueue
        
        let fixedCombinedReadStates = Atomic<MessageHistoryViewReadState?>(value: nil)
        
        var additionalData: [AdditionalMessageHistoryViewData] = []
        if case let .peer(peerId) = chatLocation {
            additionalData.append(.cachedPeerData(peerId))
            additionalData.append(.cachedPeerDataMessages(peerId))
            additionalData.append(.peerNotificationSettings(peerId))
            additionalData.append(.preferencesEntry(ApplicationSpecificPreferencesKeys.inAppNotificationSettings))
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                additionalData.append(.cacheEntry(cachedChannelAdminIdsEntryId(peerId: peerId)))
                additionalData.append(.peer(peerId))
            }
            if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.SecretChat {
                additionalData.append(.peerIsContact(peerId))
            }
        }
        additionalData.append(.totalUnreadState)
        
        let historyViewUpdate = self.chatHistoryLocation
        |> distinctUntilChanged
        |> mapToSignal { location in
            return chatHistoryViewForLocation(location, account: account, chatLocation: chatLocation, fixedCombinedReadStates: fixedCombinedReadStates.with { $0 }, tagMask: tagMask, additionalData: additionalData)
            |> beforeNext { viewUpdate in
                switch viewUpdate {
                    case let .HistoryView(view, _, _, _, _):
                        let _ = fixedCombinedReadStates.swap(view.fixedReadStates)
                    default:
                        break
                }
            }
        }
        
        let previousView = Atomic<ChatHistoryView?>(value: nil)
        let automaticDownloadNetworkType = account.networkType
        |> map { type -> AutomaticDownloadNetworkType in
            switch type {
                case .none, .wifi:
                    return .wifi
                case .cellular:
                    return .cellular
            }
        }
        |> distinctUntilChanged
        
        let historyViewTransition = combineLatest(historyViewUpdate, self.chatPresentationDataPromise.get(), selectedMessages, automaticDownloadNetworkType)
        |> mapToQueue { [weak self] update, chatPresentationData, selectedMessages, networkType -> Signal<ChatHistoryListViewTransition, NoError> in
            let initialData: ChatHistoryCombinedInitialData?
            switch update {
                case let .Loading(combinedInitialData):
                    initialData = combinedInitialData
                    Queue.mainQueue().async { [weak self] in
                        if let strongSelf = self {
                            if !strongSelf.didSetInitialData {
                                strongSelf.didSetInitialData = true
                                strongSelf._initialData.set(.single(combinedInitialData))
                            }
                            
                            strongSelf._cachedPeerDataAndMessages.set(.single((nil, nil)))
                            
                            let loadState: ChatHistoryNodeLoadState = .loading
                            if strongSelf.loadState != loadState {
                                strongSelf.loadState = loadState
                                strongSelf.loadStateUpdated?(loadState, false)
                            }
                            
                            let historyState: ChatHistoryNodeHistoryState = .loading
                            if strongSelf.currentHistoryState != historyState {
                                strongSelf.currentHistoryState = historyState
                                strongSelf.historyState.set(historyState)
                            }
                        }
                    }
                    return .complete()
                case let .HistoryView(view, type, scrollPosition, originalScrollPosition, data):
                    initialData = data
                    var updatedScrollPosition = scrollPosition
                    
                    var reverse = false
                    var includeSearchEntry = false
                    if case let .list(search, reverseValue) = mode {
                        includeSearchEntry = search
                        reverse = reverseValue
                    }
                    
                    let associatedData = extractAssociatedData(chatLocation: chatLocation, view: view, automaticDownloadNetworkType: networkType)
                    
                    let processedView = ChatHistoryView(originalView: view, filteredEntries: chatHistoryEntriesForView(location: chatLocation, view: view, includeUnreadEntry: mode == .bubbles, includeEmptyEntry: mode == .bubbles && tagMask == nil, includeChatInfoEntry: mode == .bubbles, includeSearchEntry: includeSearchEntry && tagMask != nil, reverse: reverse, groupMessages: mode == .bubbles, selectedMessages: selectedMessages, presentationData: chatPresentationData), associatedData: associatedData)
                    let previous = previousView.swap(processedView)
                    
                    if scrollPosition == nil, let originalScrollPosition = originalScrollPosition {
                        switch originalScrollPosition {
                            case let .index(index, position, _, _):
                                if case .upperBound = index {
                                    if let previous = previous, previous.filteredEntries.count == 1, case .HoleEntry = previous.filteredEntries[0] {
                                        updatedScrollPosition = .index(index: index, position: position, directionHint: .Down, animated: false)
                                    }
                                }
                            default:
                                break
                        }
                    }
                    
                    let reason: ChatHistoryViewTransitionReason
                    var prepareOnMainQueue = false
                    
                    if let previous = previous, previous.originalView.entries == processedView.originalView.entries {
                        reason = ChatHistoryViewTransitionReason.InteractiveChanges
                        updatedScrollPosition = nil
                    } else {
                        switch type {
                            case let .Initial(fadeIn):
                                reason = ChatHistoryViewTransitionReason.Initial(fadeIn: fadeIn)
                                prepareOnMainQueue = !fadeIn
                            case let .Generic(genericType):
                                switch genericType {
                                    case .InitialUnread:
                                        reason = ChatHistoryViewTransitionReason.Initial(fadeIn: false)
                                    case .Generic:
                                        reason = ChatHistoryViewTransitionReason.InteractiveChanges
                                    case .UpdateVisible:
                                        reason = ChatHistoryViewTransitionReason.Reload
                                    case let .FillHole(insertions, deletions):
                                        reason = ChatHistoryViewTransitionReason.HoleChanges(filledHoleDirections: insertions, removeHoleDirections: deletions)
                                }
                        }
                    }
                    
                    return preparedChatHistoryViewTransition(from: previous, to: processedView, reason: reason, reverse: reverse, account: account, chatLocation: chatLocation, controllerInteraction: controllerInteraction, scrollPosition: updatedScrollPosition, initialData: initialData?.initialData, keyboardButtonsMessage: view.topTaggedMessages.first, cachedData: initialData?.cachedData, cachedDataMessages: initialData?.cachedDataMessages, readStateData: initialData?.readStateData) |> map({ mappedChatHistoryViewListTransition(account: account, chatLocation: chatLocation, associatedData: associatedData, controllerInteraction: controllerInteraction, mode: mode, transition: $0) }) |> runOn(prepareOnMainQueue ? Queue.mainQueue() : messageViewQueue)
            }
        }
        
        let appliedTransition = historyViewTransition |> deliverOnMainQueue |> mapToQueue { [weak self] transition -> Signal<Void, NoError> in
            if let strongSelf = self {
                return strongSelf.enqueueHistoryViewTransition(transition)
            }
            return .complete()
        }
        
        self.historyDisposable.set(appliedTransition.start())
        
        let previousMaxIncomingMessageIndexByNamespace = Atomic<[MessageId.Namespace: MessageIndex]>(value: [:])
        let readHistory = combineLatest(self.maxVisibleIncomingMessageIndex.get(), self.canReadHistory.get())
            |> map { messageIndex, canRead in
                if canRead {
                    var apply = false
                    let _ = previousMaxIncomingMessageIndexByNamespace.modify { dict in
                        let previousIndex = dict[messageIndex.id.namespace]
                        if previousIndex == nil || previousIndex! < messageIndex {
                            apply = true
                            var dict = dict
                            dict[messageIndex.id.namespace] = messageIndex
                            return dict
                        }
                        return dict
                    }
                    if apply {
                        switch chatLocation {
                            case .peer:
                                let _ = applyMaxReadIndexInteractively(postbox: account.postbox, stateManager: account.stateManager, index: messageIndex).start()
                            case let .group(groupId):
                                let _ = account.postbox.transaction({ transaction -> Void in
                                    transaction.applyGroupFeedInteractiveReadMaxIndex(groupId: groupId, index: messageIndex)
                                }).start()
                        }
                    }
                }
        }
        
        self.readHistoryDisposable.set(readHistory.start())
        
        self.canReadHistoryDisposable = (self.canReadHistory.get() |> deliverOnMainQueue).start(next: { [weak self] value in
            if let strongSelf = self {
                if strongSelf.canReadHistoryValue != value {
                    strongSelf.canReadHistoryValue = value
                    strongSelf.updateReadHistoryActions()
                }
            }
        })
        
        if let messageId = messageId {
            self._chatHistoryLocation.set(ChatHistoryLocation.InitialSearch(location: .id(messageId), count: 60))
        } else {
            self._chatHistoryLocation.set(ChatHistoryLocation.Initial(count: 60))
        }
        
        self.displayedItemRangeChanged = { [weak self] displayedRange, opaqueTransactionState in
            if let strongSelf = self {
                if let historyView = (opaqueTransactionState as? ChatHistoryTransactionOpaqueState)?.historyView {
                    if let visible = displayedRange.visibleRange {
                        let indexRange = (historyView.filteredEntries.count - 1 - visible.lastIndex, historyView.filteredEntries.count - 1 - visible.firstIndex)
                        
                        var readIndexRange = (0, historyView.filteredEntries.count - 1 - visible.firstIndex)
                        /*if !visible.firstIndexFullyVisible {
                            readIndexRange.1 -= 1
                        }*/
                        
                        var messageIdsWithViewCount: [MessageId] = []
                        var messageIdsWithUnseenPersonalMention: [MessageId] = []
                        for i in (indexRange.0 ... indexRange.1) {
                            switch historyView.filteredEntries[i] {
                                case let .MessageEntry(message, _, _, _, _, _):
                                    var hasUnconsumedMention = false
                                    var hasUnconsumedContent = false
                                    if message.tags.contains(.unseenPersonalMessage) {
                                        for attribute in message.attributes {
                                            if let attribute = attribute as? ConsumablePersonalMentionMessageAttribute, !attribute.pending {
                                                hasUnconsumedMention = true
                                            }
                                        }
                                    }
                                    for attribute in message.attributes {
                                        if attribute is ViewCountMessageAttribute {
                                            if message.id.namespace == Namespaces.Message.Cloud {
                                                messageIdsWithViewCount.append(message.id)
                                            }
                                        } else if let attribute = attribute as? ConsumableContentMessageAttribute, !attribute.consumed {
                                            hasUnconsumedContent = true
                                        }
                                    }
                                    if hasUnconsumedMention && !hasUnconsumedContent {
                                        messageIdsWithUnseenPersonalMention.append(message.id)
                                    }
                                case let .MessageGroupEntry(_, messages, _):
                                    for (message, _, _, _) in messages {
                                        var hasUnconsumedMention = false
                                        var hasUnconsumedContent = false
                                        if message.tags.contains(.unseenPersonalMessage) {
                                            for attribute in message.attributes {
                                                if let attribute = attribute as? ConsumablePersonalMentionMessageAttribute, !attribute.pending {
                                                    hasUnconsumedMention = true
                                                }
                                            }
                                        }
                                        for attribute in message.attributes {
                                            if attribute is ViewCountMessageAttribute {
                                                if message.id.namespace == Namespaces.Message.Cloud {
                                                    messageIdsWithViewCount.append(message.id)
                                                }
                                            } else if let attribute = attribute as? ConsumableContentMessageAttribute, !attribute.consumed {
                                                hasUnconsumedContent = true
                                            }
                                        }
                                        if hasUnconsumedMention && !hasUnconsumedContent {
                                            messageIdsWithUnseenPersonalMention.append(message.id)
                                        }
                                    }
                                default:
                                    break
                            }
                        }
                        
                        if !messageIdsWithViewCount.isEmpty {
                            strongSelf.messageProcessingManager.add(messageIdsWithViewCount)
                        }
                        
                        if !messageIdsWithUnseenPersonalMention.isEmpty {
                            strongSelf.messageMentionProcessingManager.add(messageIdsWithUnseenPersonalMention)
                        }
                        
                        if readIndexRange.0 <= readIndexRange.1 {
                            let (maxIncomingIndex, maxOverallIndex) = maxMessageIndexForEntries(historyView.filteredEntries, indexRange: readIndexRange)
                            
                            if let maxIncomingIndex = maxIncomingIndex {
                                strongSelf.updateMaxVisibleReadIncomingMessageIndex(maxIncomingIndex)
                            }
                            
                            if let maxOverallIndex = maxOverallIndex, maxOverallIndex != strongSelf.maxVisibleMessageIndexReported {
                                strongSelf.maxVisibleMessageIndexReported = maxOverallIndex
                                strongSelf.maxVisibleMessageIndexUpdated?(maxOverallIndex)
                            }
                        }
                    }
                    
                    if let loaded = displayedRange.loadedRange, let firstEntry = historyView.filteredEntries.first, let lastEntry = historyView.filteredEntries.last {
                        if loaded.firstIndex < 5 && historyView.originalView.laterId != nil {
                            strongSelf._chatHistoryLocation.set(ChatHistoryLocation.Navigation(index: .message(lastEntry.index), anchorIndex: .message(lastEntry.index), count: historyMessageCount))
                        } else if loaded.lastIndex >= historyView.filteredEntries.count - 5 && historyView.originalView.earlierId != nil {
                            strongSelf._chatHistoryLocation.set(ChatHistoryLocation.Navigation(index: .message(firstEntry.index), anchorIndex: .message(firstEntry.index), count: historyMessageCount))
                        }
                    }
                }
            }
        }
        
        self.presentationDataDisposable = (account.telegramApplicationContext.presentationData
            |> deliverOnMainQueue).start(next: { [weak self] presentationData in
                if let strongSelf = self {
                    let previousTheme = strongSelf.currentPresentationData.theme
                    let previousStrings = strongSelf.currentPresentationData.strings
                    let previousWallpaper = strongSelf.currentPresentationData.chatWallpaper
                    let previousDisableAnimations = strongSelf.currentPresentationData.disableAnimations
                    
                    strongSelf.currentPresentationData = presentationData
                    
                    if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings || previousWallpaper != presentationData.chatWallpaper || previousDisableAnimations != presentationData.disableAnimations {
                        let themeData = ChatPresentationThemeData(theme: presentationData.theme, wallpaper: presentationData.chatWallpaper)
                        let chatPresentationData = ChatPresentationData(theme: themeData, fontSize: presentationData.fontSize, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, disableAnimations: presentationData.disableAnimations)
                        
                        strongSelf.dynamicBounceEnabled = !presentationData.disableAnimations
                        
                        strongSelf.forEachItemHeaderNode { itemHeaderNode in
                            if let dateNode = itemHeaderNode as? ChatMessageDateHeaderNode {
                                dateNode.updatePresentationData(chatPresentationData)
                            } else if let dateNode = itemHeaderNode as? ListMessageDateHeaderNode {
                                dateNode.updateThemeAndStrings(theme: presentationData.theme, strings: presentationData.strings)
                            }
                        }
                        strongSelf.chatPresentationDataPromise.set(.single(chatPresentationData))
                    }
                }
            })
        
        self.visibleContentOffsetChanged = { [weak self] offset in
            if let strongSelf = self {
                strongSelf.contentPositionChanged(offset)
                
                if strongSelf.tagMask == nil {
                    var atBottom = false
                    switch offset {
                        case let .known(offsetValue):
                            if offsetValue.isLessThanOrEqualTo(0.0) {
                                atBottom = true
                            }
                        default:
                            break
                    }
                    
                    if atBottom != strongSelf.isScrollAtBottomPosition {
                        strongSelf.isScrollAtBottomPosition = atBottom
                        strongSelf.updateReadHistoryActions()
                        
                        strongSelf.isScrollAtBottomPositionUpdated?()
                    }
                }
            }
        }
        
        self.loadedMessagesFromCachedDataDisposable = (self._cachedPeerDataAndMessages.get() |> map { dataAndMessages -> MessageId? in
            return dataAndMessages.0?.messageIds.first
        } |> distinctUntilChanged(isEqual: { $0 == $1 })
        |> mapToSignal { messageId -> Signal<Void, NoError> in
            if let messageId = messageId {
                return getMessagesLoadIfNecessary([messageId], postbox: account.postbox, network: account.network, accountPeerId: account.peerId) |> map { _ -> Void in return Void() }
            } else {
                return .complete()
            }
        }).start()
    }
    
    deinit {
        self.historyDisposable.dispose()
        self.readHistoryDisposable.dispose()
        self.interactiveReadActionDisposable?.dispose()
        self.canReadHistoryDisposable?.dispose()
        self.loadedMessagesFromCachedDataDisposable?.dispose()
    }
    
    public func setLoadStateUpdated(_ f: @escaping (ChatHistoryNodeLoadState, Bool) -> Void) {
        self.loadStateUpdated = f
    }
    
    public func scrollScreenToTop() {
        var currentMessage: Message?
        if let historyView = self.historyView {
            if let visibleRange = self.displayedItemRange.loadedRange {
                var index = historyView.filteredEntries.count - 1
                loop: for entry in historyView.filteredEntries {
                    if index >= visibleRange.firstIndex && index <= visibleRange.lastIndex {
                        if case let .MessageEntry(message, _, _, _, _, _) = entry {
                            currentMessage = message
                            break loop
                        } else if case let .MessageGroupEntry(_, messages, _) = entry {
                            currentMessage = messages.first?.0
                            break loop
                        }
                    }
                    index -= 1
                }
            }
        }
        
        if let currentMessage = currentMessage {
            self._chatHistoryLocation.set(ChatHistoryLocation.Scroll(index: .message(MessageIndex(currentMessage)), anchorIndex: .message(MessageIndex(currentMessage)), sourceIndex: .upperBound, scrollPosition: .top(0.0), animated: true))
        }
    }
    
    public func scrollToStartOfHistory() {
        self._chatHistoryLocation.set(ChatHistoryLocation.Scroll(index: .lowerBound, anchorIndex: .lowerBound, sourceIndex: .upperBound, scrollPosition: .bottom(0.0), animated: true))
    }
    
    public func scrollToEndOfHistory() {
        switch self.visibleContentOffset() {
            case .known(0.0):
                break
            default:
                self._chatHistoryLocation.set(ChatHistoryLocation.Scroll(index: .upperBound, anchorIndex: .upperBound, sourceIndex: .lowerBound, scrollPosition: .top(0.0), animated: true))
        }
    }
    
    public func scrollToMessage(from fromIndex: MessageIndex, to toIndex: MessageIndex, animated: Bool, highlight: Bool = true, scrollPosition: ListViewScrollPosition = .center(.bottom)) {
        self._chatHistoryLocation.set(ChatHistoryLocation.Scroll(index: .message(toIndex), anchorIndex: .message(toIndex), sourceIndex: .message(fromIndex), scrollPosition: scrollPosition, animated: animated))
    }
    
    func scrollWithDeltaOffset(_ offset: CGFloat) {

    }
    
    public func anchorMessageInCurrentHistoryView() -> Message? {
        if let historyView = self.historyView {
            if let visibleRange = self.displayedItemRange.visibleRange {
                var index = 0
                for entry in historyView.filteredEntries.reversed() {
                    if index >= visibleRange.firstIndex && index <= visibleRange.lastIndex {
                        if case let .MessageEntry(message, _, _, _, _, _) = entry {
                            return message
                        }
                    }
                    index += 1
                }
            }
            
            for case let .MessageEntry(message, _, _, _, _, _) in historyView.filteredEntries {
                return message
            }
        }
        return nil
    }
    
    public func isMessageVisibleOnScreen(_ id: MessageId) -> Bool {
        var result = false
        self.forEachItemNode({ itemNode in
            if let itemNode = itemNode as? ChatMessageItemView, let item = itemNode.item, item.content.contains(where: { $0.id == id }) {
                if self.itemNodeVisibleInsideInsets(itemNode) {
                    result = true
                }
            }
        })
        return result
    }
    
    public func messageInCurrentHistoryView(_ id: MessageId) -> Message? {
        if let historyView = self.historyView {
            for entry in historyView.filteredEntries {
                if case let .MessageEntry(message, _, _, _, _, _) = entry {
                    if message.id == id {
                        return message
                    }
                } else if case let .MessageGroupEntry(_, messages, _) = entry {
                    for (message, _, _, _) in messages {
                        if message.id == id {
                            return message
                        }
                    }
                }
            }
        }
        return nil
    }
    
    public func messageGroupInCurrentHistoryView(_ id: MessageId) -> [Message]? {
        if let historyView = self.historyView {
            for entry in historyView.filteredEntries {
                if case let .MessageEntry(message, _, _, _, _, _) = entry {
                    if message.id == id {
                        return [message]
                    }
                } else if case let .MessageGroupEntry(_, messages, _) = entry {
                    for (message, _, _, _) in messages {
                        if message.id == id {
                            return messages.map { $0.0 }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    public func forEachMessageInCurrentHistoryView(_ f: (Message) -> Bool) {
        if let historyView = self.historyView {
            for entry in historyView.filteredEntries {
                if case let .MessageEntry(message, _, _, _, _, _) = entry {
                    if !f(message) {
                        return
                    }
                } else if case let .MessageGroupEntry(_, messages, _) = entry {
                    for (message, _, _, _) in messages {
                        if !f(message) {
                            return
                        }
                    }
                }
            }
        }
    }
    
    private func updateMaxVisibleReadIncomingMessageIndex(_ index: MessageIndex) {
        self.maxVisibleIncomingMessageIndex.set(index)
    }
    
    private func enqueueHistoryViewTransition(_ transition: ChatHistoryListViewTransition) -> Signal<Void, NoError> {
        return Signal { [weak self] subscriber in
            if let strongSelf = self {
                if let _ = strongSelf.enqueuedHistoryViewTransition {
                    preconditionFailure()
                }
                
                if !strongSelf.didSetInitialData {
                    strongSelf.didSetInitialData = true
                    strongSelf._initialData.set(.single(ChatHistoryCombinedInitialData(initialData: transition.initialData, buttonKeyboardMessage: transition.keyboardButtonsMessage, cachedData: transition.cachedData, cachedDataMessages: transition.cachedDataMessages, readStateData: transition.readStateData)))
                }
                
                strongSelf.enqueuedHistoryViewTransition = (transition, {
                    if let scrolledToIndex = transition.scrolledToIndex {
                        if let strongSelf = self {
                            strongSelf.scrolledToIndex?(scrolledToIndex)
                        }
                    }
                    subscriber.putCompletion()
                })
                
                if strongSelf.isNodeLoaded {
                    strongSelf.dequeueHistoryViewTransition()
                } else {
                    strongSelf._cachedPeerDataAndMessages.set(.single((transition.cachedData, transition.cachedDataMessages)))
                    
                    let loadState: ChatHistoryNodeLoadState
                    if transition.historyView.filteredEntries.isEmpty {
                        loadState = .empty
                    } else {
                        loadState = .messages
                    }
                    if strongSelf.loadState != loadState {
                        strongSelf.loadState = loadState
                        strongSelf.loadStateUpdated?(loadState, transition.options.contains(.AnimateInsertion))
                    }
                    
                    let historyState: ChatHistoryNodeHistoryState = .loaded(isEmpty: transition.historyView.originalView.entries.isEmpty)
                    if strongSelf.currentHistoryState != historyState {
                        strongSelf.currentHistoryState = historyState
                        strongSelf.historyState.set(historyState)
                    }
                }
            } else {
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        } |> runOn(Queue.mainQueue())
    }
    
    private func dequeueHistoryViewTransition() {
        if let (transition, completion) = self.enqueuedHistoryViewTransition {
            self.enqueuedHistoryViewTransition = nil
            
            let animated = transition.options.contains(.AnimateInsertion)
            
            let completion: (ListViewDisplayedItemRange) -> Void = { [weak self] visibleRange in
                if let strongSelf = self {
                    strongSelf.historyView = transition.historyView
                    
                    let loadState: ChatHistoryNodeLoadState
                    if let historyView = strongSelf.historyView {
                        if historyView.filteredEntries.isEmpty {
                            loadState = .empty
                        } else {
                            loadState = .messages
                        }
                    } else {
                        loadState = .loading
                    }
                    
                    if strongSelf.loadState != loadState {
                        strongSelf.loadState = loadState
                        strongSelf.loadStateUpdated?(loadState, animated)
                    }
                    
                    if let range = visibleRange.loadedRange {
                        strongSelf.account.postbox.updateMessageHistoryViewVisibleRange(transition.historyView.originalView.id, earliestVisibleIndex: transition.historyView.filteredEntries[transition.historyView.filteredEntries.count - 1 - range.lastIndex].index, latestVisibleIndex: transition.historyView.filteredEntries[transition.historyView.filteredEntries.count - 1 - range.firstIndex].index)
                        
                        if let visible = visibleRange.visibleRange {
                            var visibleFirstIndex = visible.firstIndex
                            /*if !visible.firstIndexFullyVisible {
                                visibleFirstIndex += 1
                            }*/
                            if visibleFirstIndex <= visible.lastIndex {
                                let (messageIndex, _) =  maxMessageIndexForEntries(transition.historyView.filteredEntries, indexRange: (transition.historyView.filteredEntries.count - 1 - visible.lastIndex, transition.historyView.filteredEntries.count - 1 - visibleFirstIndex))
                                if let messageIndex = messageIndex {
                                    strongSelf.updateMaxVisibleReadIncomingMessageIndex(messageIndex)
                                }
                            }
                        }
                    }
                    if !strongSelf.didSetInitialData {
                        strongSelf.didSetInitialData = true
                        strongSelf._initialData.set(.single(ChatHistoryCombinedInitialData(initialData: transition.initialData, buttonKeyboardMessage: transition.keyboardButtonsMessage, cachedData: transition.cachedData, cachedDataMessages: transition.cachedDataMessages, readStateData: transition.readStateData)))
                    }
                    strongSelf._cachedPeerDataAndMessages.set(.single((transition.cachedData, transition.cachedDataMessages)))
                    let historyState: ChatHistoryNodeHistoryState = .loaded(isEmpty: transition.historyView.originalView.entries.isEmpty)
                    if strongSelf.currentHistoryState != historyState {
                        strongSelf.currentHistoryState = historyState
                        strongSelf.historyState.set(historyState)
                    }
                    
                    var buttonKeyboardMessageUpdated = false
                    if let currentButtonKeyboardMessage = strongSelf.currentButtonKeyboardMessage, let buttonKeyboardMessage = transition.keyboardButtonsMessage {
                        if currentButtonKeyboardMessage.id != buttonKeyboardMessage.id || currentButtonKeyboardMessage.stableVersion != buttonKeyboardMessage.stableVersion {
                            buttonKeyboardMessageUpdated = true
                        }
                    } else if (strongSelf.currentButtonKeyboardMessage != nil) != (transition.keyboardButtonsMessage != nil) {
                        buttonKeyboardMessageUpdated = true
                    }
                    if buttonKeyboardMessageUpdated {
                        strongSelf.currentButtonKeyboardMessage = transition.keyboardButtonsMessage
                        strongSelf._buttonKeyboardMessage.set(.single(transition.keyboardButtonsMessage))
                    }
                    
                    if transition.animateIn {
                        strongSelf.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                    }
                    
                    completion()
                }
            }
            
            if let layoutActionOnViewTransition = self.layoutActionOnViewTransition {
                self.layoutActionOnViewTransition = nil
                let (mappedTransition, updateSizeAndInsets) = layoutActionOnViewTransition(transition)
                
                self.transaction(deleteIndices: mappedTransition.deleteItems, insertIndicesAndItems: transition.insertItems, updateIndicesAndItems: transition.updateItems, options: mappedTransition.options, scrollToItem: mappedTransition.scrollToItem, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: mappedTransition.stationaryItemRange, updateOpaqueState: ChatHistoryTransactionOpaqueState(historyView: transition.historyView), completion: completion)
            } else {
                self.transaction(deleteIndices: transition.deleteItems, insertIndicesAndItems: transition.insertItems, updateIndicesAndItems: transition.updateItems, options: transition.options, scrollToItem: transition.scrollToItem, stationaryItemRange: transition.stationaryItemRange, updateOpaqueState: ChatHistoryTransactionOpaqueState(historyView: transition.historyView), completion: completion)
            }
        }
    }
    
    public func updateLayout(transition: ContainedViewLayoutTransition, updateSizeAndInsets: ListViewUpdateSizeAndInsets) {
        self.updateLayout(transition: transition, updateSizeAndInsets: updateSizeAndInsets, additionalScrollDistance: 0.0, scrollToTop: false)
    }
        
    public func updateLayout(transition: ContainedViewLayoutTransition, updateSizeAndInsets: ListViewUpdateSizeAndInsets, additionalScrollDistance: CGFloat, scrollToTop: Bool) {
        var scrollToItem: ListViewScrollToItem?
        if scrollToTop, case .known = self.visibleContentOffset() {
            scrollToItem = ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Spring(duration: updateSizeAndInsets.duration), directionHint: .Up)
        }
        self.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: scrollToItem, additionalScrollDistance: scrollToTop ? 0.0 : additionalScrollDistance, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !self.dequeuedInitialTransitionOnLayout {
            self.dequeuedInitialTransitionOnLayout = true
            self.dequeueHistoryViewTransition()
        }
    }
    
    public func disconnect() {
        self.historyDisposable.set(nil)
    }
    
    private func updateReadHistoryActions() {
        let canRead = self.canReadHistoryValue && self.isScrollAtBottomPosition
        if canRead != (self.interactiveReadActionDisposable != nil) {
            if let interactiveReadActionDisposable = self.interactiveReadActionDisposable {
                if !canRead {
                    interactiveReadActionDisposable.dispose()
                    self.interactiveReadActionDisposable = nil
                }
            } else if self.interactiveReadActionDisposable == nil {
                if case let .peer(peerId) = self.chatLocation {
                    self.interactiveReadActionDisposable = installInteractiveReadMessagesAction(postbox: self.account.postbox, stateManager: self.account.stateManager, peerId: peerId)
                }
            }
        }
    }
    
    func immediateScrollState() -> ChatInterfaceHistoryScrollState? {
        var currentMessage: Message?
        if let historyView = self.historyView {
            if let visibleRange = self.displayedItemRange.visibleRange {
                var index = 0
                loop: for entry in historyView.filteredEntries.reversed() {
                    if index >= visibleRange.firstIndex && index <= visibleRange.lastIndex {
                        if case let .MessageEntry(message, _, _, _, _, _) = entry {
                            if index != 0 || historyView.originalView.laterId != nil {
                                currentMessage = message
                            }
                            break loop
                        } else if case let .MessageGroupEntry(_, messages, _) = entry {
                            if index != 0 || historyView.originalView.laterId != nil {
                                currentMessage = messages.first?.0
                            }
                            break loop
                        }
                    }
                    index += 1
                }
            }
        }
        
        if let message = currentMessage {
            var relativeOffset: CGFloat = 0.0
            self.forEachItemNode { itemNode in
                if let itemNode = itemNode as? ChatMessageItemView, let item = itemNode.item, item.message.id == message.id {
                    if let offsetValue = self.itemNodeRelativeOffset(itemNode) {
                        relativeOffset = offsetValue
                    }
                }
            }
            return ChatInterfaceHistoryScrollState(messageIndex: MessageIndex(message), relativeOffset: Double(relativeOffset))
        }
        return nil
    }
    
    func scrollToNextMessage() {
        if let historyView = self.historyView {
            var scrolled = false
            if let scrollState = self.immediateScrollState() {
                var index = historyView.filteredEntries.count - 1
                loop: for entry in historyView.filteredEntries.reversed() {
                    if entry.index == scrollState.messageIndex {
                        break loop
                    }
                    index -= 1
                }
                
                if index != 0 {
                    var nextItem = false
                    self.forEachItemNode { itemNode in
                        if let itemNode = itemNode as? ChatMessageItemView, itemNode.item?.content.index == scrollState.messageIndex {
                            if itemNode.frame.maxY >= self.bounds.size.height - self.insets.bottom - 4.0 {
                                nextItem = true
                            }
                        }
                    }
                    
                    if !nextItem {
                        scrolled = true
                        self.scrollToMessage(from: scrollState.messageIndex, to: scrollState.messageIndex, animated: true, highlight: false)
                    } else {
                        loop: for i in (index + 1) ..< historyView.filteredEntries.count {
                            let entry = historyView.filteredEntries[i]
                            switch entry {
                                case .MessageEntry, .MessageGroupEntry:
                                    scrolled = true
                                    self.scrollToMessage(from: scrollState.messageIndex, to: entry.index, animated: true, highlight: false)
                                    break loop
                                default:
                                    break
                            }
                        }
                    }
                }
            }
            
            if !scrolled {
                self.scrollToEndOfHistory()
            }
        }
    }
    
    func requestMessageUpdate(_ id: MessageId) {
        if let historyView = self.historyView {
            var messageItem: ChatMessageItem?
            self.forEachItemNode({ itemNode in
                if let itemNode = itemNode as? ChatMessageItemView, let item = itemNode.item {
                    for message in item.content {
                        if message.id == id {
                            messageItem = item
                            break
                        }
                    }
                }
            })
            
            if let messageItem = messageItem {
                let associatedData = messageItem.associatedData
                
                loop: for i in 0 ..< historyView.filteredEntries.count {
                    switch historyView.filteredEntries[i] {
                        case let .MessageEntry(message, presentationData, read, _, selection, isAdmin):
                            if message.id == id {
                                let index = historyView.filteredEntries.count - 1 - i
                                let item: ListViewItem
                                switch self.mode {
                                    case .bubbles:
                                        item = ChatMessageItem(presentationData: presentationData, account: self.account, chatLocation: self.chatLocation, associatedData: associatedData, controllerInteraction: self.controllerInteraction, content: .message(message: message, read: read, selection: selection, isAdmin: isAdmin))
                                    case let .list(search, _):
                                        item = ListMessageItem(theme: presentationData.theme.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, account: self.account, chatLocation: self.chatLocation, controllerInteraction: self.controllerInteraction, message: message, selection: selection, displayHeader: search)
                                }
                                let updateItem = ListViewUpdateItem(index: index, previousIndex: index, item: item, directionHint: nil)
                                self.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [updateItem], options: [.AnimateInsertion], scrollToItem: nil, additionalScrollDistance: 0.0, updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
                                break loop
                            }
                        default:
                            break
                    }
                }
            }
        }
    }
}
