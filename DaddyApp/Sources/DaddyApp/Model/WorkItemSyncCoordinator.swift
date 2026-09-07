import Foundation
import AppKit
import DaddyCore

/// Owns the OAuth token lifecycle so `GoogleDriveClient`'s access-token
/// closure can call it from any queue without touching the `@MainActor`
/// coordinator below.
final class GoogleDriveTokenProvider: @unchecked Sendable {
    private let oauthClient: GoogleOAuthClient
    private let lock = NSLock()
    private var accessToken: String?
    private var accessTokenExpiresAt: Date?
    private var refreshToken: String?

    init(oauthClient: GoogleOAuthClient, refreshToken: String?) {
        self.oauthClient = oauthClient
        self.refreshToken = refreshToken
    }

    func setRefreshToken(_ token: String?) {
        lock.withLock {
            refreshToken = token
            accessToken = nil
            accessTokenExpiresAt = nil
        }
    }

    func currentAccessToken() async throws -> String {
        let cached = lock.withLock { (accessToken, accessTokenExpiresAt, refreshToken) }

        if let cachedToken = cached.0, let cachedExpiry = cached.1, cachedExpiry > Date().addingTimeInterval(60) {
            return cachedToken
        }
        guard let refresh = cached.2 else { throw GoogleOAuthClient.ClientError.userCancelled }

        let tokens = try await oauthClient.refreshAccessToken(refresh)
        lock.withLock {
            accessToken = tokens.accessToken
            accessTokenExpiresAt = tokens.expiresAt
            if let newRefresh = tokens.refreshToken { refreshToken = newRefresh }
        }
        return tokens.accessToken
    }
}

/// The only thing that talks to both the local Markdown store and Drive.
/// `OrchestratorMarkdownStore` stays a pure local cache/backup — every write
/// lands there first and unconditionally — while this coordinator attempts
/// the matching Drive call and, on failure, queues it (persisted, so a quit
/// while offline doesn't drop the intent to sync) for `flushPendingSync()`
/// to replay later.
@MainActor
final class WorkItemSyncCoordinator {
    private static let rootFolderName = "Daddy Kanban"

    private let localStore: OrchestratorMarkdownStore
    private let localQueue = DispatchQueue(label: "daddy.work-items.local", qos: .utility)
    private let oauthClient: GoogleOAuthClient
    private let credentialStore = GoogleDriveCredentialStore()
    private let index = DriveSyncIndex()
    private let tokenProvider: GoogleDriveTokenProvider

    private(set) var driveClient: GoogleDriveClient?
    private var entries: [String: DriveSyncEntry]
    private var pending: Set<CategoryBucket>

    /// A token is on disk, whether or not it has been unlocked this session.
    private var hasStoredCredential: Bool

    /// Set when the fingerprint is declined, cleared by an explicit "Sync now"
    /// or a reconnect. Keeps a dismissal from turning into a prompt per save.
    private var authDeclinedThisSession = false

    /// Connected means "there is a credential", not "it is unlocked right now".
    /// Otherwise the drawer would report disconnected until you happened to
    /// authenticate, and offer to run the OAuth flow all over again.
    var isConnected: Bool { driveClient != nil || hasStoredCredential }
    var pendingSyncCount: Int { pending.count }
    var pendingBuckets: Set<CategoryBucket> { pending }

    /// Forces an immediate retry of whatever's queued, rather than waiting
    /// for the next throttled `tick()`. Used by the manual "sync now" button.
    func syncNow() async {
        authDeclinedThisSession = false
        await flushPendingSync()
    }

    init(localStore: OrchestratorMarkdownStore) {
        self.localStore = localStore
        let oauthClient = GoogleOAuthClient(
            clientID: GoogleDriveConfig.clientID,
            clientSecret: GoogleDriveConfig.clientSecret,
            scope: GoogleDriveConfig.scope
        )
        self.oauthClient = oauthClient

        // Note what exists; do not read it.
        //
        // Constructing this coordinator is what the settings drawer does just
        // to ask whether Drive is connected, and making that question cost a
        // fingerprint is not a trade worth making. The token is read on the
        // first request that actually needs it — see `unlockIfNeeded()`.
        self.hasStoredCredential = credentialStore.hasStoredToken()
        self.tokenProvider = GoogleDriveTokenProvider(oauthClient: oauthClient, refreshToken: nil)

        self.entries = Dictionary(uniqueKeysWithValues: index.loadEntries().map { ($0.localID, $0) })
        self.pending = Set(index.loadPendingBuckets().map {
            CategoryBucket(projectFolderName: $0.projectFolderName, categoryFolderName: $0.categoryFolderName)
        })
    }

    /// Reads the stored token behind Touch ID and builds the Drive client.
    ///
    /// Returns false when there is nothing stored, or the fingerprint was
    /// declined — callers fall back to local-only behaviour, which is what
    /// they already did when Drive was unreachable.
    @discardableResult
    private func unlockIfNeeded() async -> Bool {
        if driveClient != nil { return true }
        guard hasStoredCredential, !authDeclinedThisSession else { return false }

        guard await credentialStore.authenticate() else {
            // Stop asking. Every card you save runs through here, and a second
            // prompt for the request right after you dismissed the first is how
            // an auth gate becomes the thing you turn off. Work keeps saving
            // locally and queues for sync; "Sync now" clears the flag.
            authDeclinedThisSession = true
            return false
        }

        guard let token = credentialStore.loadRefreshToken() else {
            // The item vanished between the existence check and the read.
            hasStoredCredential = false
            return false
        }

        tokenProvider.setRefreshToken(token)
        let provider = tokenProvider
        driveClient = GoogleDriveClient(accessTokenProvider: { try await provider.currentAccessToken() })
        return true
    }

    // MARK: - Connect / disconnect

    /// Runs the full loopback OAuth flow, opening the system browser. Returns
    /// the connected account's email for display.
    func connect() async throws -> String {
        let codeVerifier = GoogleOAuthClient.makeCodeVerifier()
        let (redirectURI, awaitCode) = try await oauthClient.startLoopbackListener()
        let authURL = oauthClient.makeAuthorizationURL(codeVerifier: codeVerifier, redirectURI: redirectURI)
        NSWorkspace.shared.open(authURL)

        let code = try await awaitCode(120)
        let tokens = try await oauthClient.exchangeCode(code, codeVerifier: codeVerifier, redirectURI: redirectURI)
        guard let refreshToken = tokens.refreshToken else {
            throw GoogleOAuthClient.ClientError.invalidResponse
        }

        credentialStore.saveRefreshToken(refreshToken)
        hasStoredCredential = true
        authDeclinedThisSession = false
        tokenProvider.setRefreshToken(refreshToken)
        let provider = tokenProvider
        driveClient = GoogleDriveClient(accessTokenProvider: { try await provider.currentAccessToken() })

        let email = tokens.idToken.flatMap(GoogleOAuthClient.decodeEmail(fromIDToken:)) ?? "Connected"
        Defaults.set(true, for: .driveConnected)
        Defaults.set(email, for: .driveAccountEmail)
        return email
    }

    func disconnect() {
        credentialStore.deleteRefreshToken()
        hasStoredCredential = false
        tokenProvider.setRefreshToken(nil)
        driveClient = nil
        Defaults.set(false, for: .driveConnected)
        Defaults.set("", for: .driveAccountEmail)
    }

    // MARK: - Reads

    /// Drive first, local cache as fallback. Also replays anything queued
    /// offline before trusting Drive's state, and pushes up any local bucket
    /// Drive doesn't know about yet (created before the first connect, or
    /// while its project folder didn't exist).
    func loadWorkItems() async -> [OrchestratorWorkItem] {
        await unlockIfNeeded()
        let localItems = localStore.loadWorkItems()
        guard let driveClient else { return localItems }

        await flushPendingSync()

        do {
            _ = try await ensureRootFolder(driveClient: driveClient)
            var driveItems: [UUID: OrchestratorWorkItem] = [:]
            var knownBuckets: Set<CategoryBucket> = []

            // `drive.file` scope means only folders this app already created
            // are visible — walk the index rather than trying to "discover"
            // arbitrary Drive content. Project folders are "folder:<project>"
            // entries with no "/" in the remainder (category folders are
            // "folder:<project>/<category>", same prefix, one level deeper).
            let projectFolders = entries.values.filter {
                $0.localID.hasPrefix("folder:") && !$0.localID.dropFirst("folder:".count).contains("/")
            }
            for projectFolder in projectFolders {
                let projectFolderName = String(projectFolder.localID.dropFirst("folder:".count))
                let children = try await driveClient.listFiles(inParent: projectFolder.driveFileID)

                for child in children where child.mimeType == GoogleDriveClient.folderMimeType {
                    let categoryFolderName = child.name
                    setEntry(DriveSyncEntry(
                        localID: "folder:\(projectFolderName)/\(categoryFolderName)",
                        driveFileID: child.id,
                        lastSyncedAt: Date()
                    ))

                    let bucket = CategoryBucket(projectFolderName: projectFolderName, categoryFolderName: categoryFolderName)
                    knownBuckets.insert(bucket)

                    let categoryFiles = try await driveClient.listFiles(inParent: child.id)
                    guard let mdFile = categoryFiles.first(where: { $0.name.hasSuffix(".md") }) else { continue }

                    let content = try await driveClient.downloadContent(fileID: mdFile.id)
                    let items = OrchestratorMarkdownStore.parseItems(content: content)
                    for item in items {
                        driveItems[item.id] = item
                        localStore.save(item)
                    }
                    setEntry(DriveSyncEntry(localID: bucketKey(bucket), driveFileID: mdFile.id, lastSyncedAt: Date()))
                }
            }

            // Local buckets Drive doesn't know about yet (created before the
            // first connect) get pushed up rather than silently dropped.
            let localBuckets = Set(localItems.map {
                CategoryBucket(
                    projectFolderName: localStore.projectFolderName(for: $0.projectID),
                    categoryFolderName: $0.category.folderName
                )
            })
            for bucket in localBuckets.subtracting(knownBuckets) {
                try? await syncCategoryBucket(bucket, driveClient: driveClient)
            }
            for local in localItems where driveItems[local.id] == nil {
                driveItems[local.id] = local
            }

            return Array(driveItems.values).sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            return localItems
        }
    }

    // MARK: - Writes

    func save(_ item: OrchestratorWorkItem) async {
        let localStore = localStore
        let buckets = await withCheckedContinuation { continuation in
            localQueue.async {
                continuation.resume(returning: localStore.save(item))
            }
        }
        enqueueBuckets(buckets)
    }

    func delete(_ item: OrchestratorWorkItem) async {
        let localStore = localStore
        let bucket = await withCheckedContinuation { continuation in
            localQueue.async {
                continuation.resume(returning: localStore.delete(item))
            }
        }
        guard let bucket else { return }
        enqueueBuckets([bucket])
    }

    /// Writes never touch Drive. They used to attempt an immediate Drive
    /// rewrite on the main actor — Touch ID prompt included — so every card
    /// create, move and edit stalled the board on network. Buckets queue here
    /// and go up on the manual "sync now" button or the 2-hour auto flush.
    private func enqueueBuckets(_ buckets: some Sequence<CategoryBucket>) {
        for bucket in buckets { enqueuePending(bucket) }
    }

    func flushPendingSync() async {
        await unlockIfNeeded()
        guard let driveClient else { return }
        for bucket in pending {
            do {
                try await syncCategoryBucket(bucket, driveClient: driveClient)
                pending.remove(bucket)
                persistIndex()
            } catch {
                // still failing — leave it queued, try again next tick
            }
        }
    }

    // MARK: - Drive folder/file mechanics

    /// Pushes a bucket's current local content to Drive: creates the file if
    /// Drive doesn't have one yet, updates it in place if it does, or deletes
    /// it if the bucket is now empty locally. This is the one place bucket
    /// content ever moves to Drive — content is always re-read fresh from
    /// disk here, never snapshotted, so there's nothing to go stale.
    private func syncCategoryBucket(_ bucket: CategoryBucket, driveClient: GoogleDriveClient) async throws {
        let localID = bucketKey(bucket)
        let content = localStore.categoryFileContent(for: bucket)

        guard let content, !content.isEmpty else {
            if let existing = entries[localID] {
                try await driveClient.deleteFile(fileID: existing.driveFileID)
                entries.removeValue(forKey: localID)
                persistIndex()
            }
            return
        }

        let rootID = try await ensureRootFolder(driveClient: driveClient)
        let projectFolderID = try await ensureFolder(
            localID: "folder:\(bucket.projectFolderName)",
            name: bucket.projectFolderName,
            parentID: rootID,
            driveClient: driveClient
        )
        let categoryFolderID = try await ensureFolder(
            localID: "folder:\(bucket.projectFolderName)/\(bucket.categoryFolderName)",
            name: bucket.categoryFolderName,
            parentID: projectFolderID,
            driveClient: driveClient
        )
        let fileName = "\(bucket.categoryFolderName).md"

        if let existing = entries[localID] {
            _ = try await driveClient.updateFileContent(fileID: existing.driveFileID, markdown: content)
            setEntry(DriveSyncEntry(localID: localID, driveFileID: existing.driveFileID, lastSyncedAt: Date()))
        } else if let found = try await driveClient.findFile(name: fileName, parentID: categoryFolderID) {
            _ = try await driveClient.updateFileContent(fileID: found.id, markdown: content)
            setEntry(DriveSyncEntry(localID: localID, driveFileID: found.id, lastSyncedAt: Date()))
        } else {
            let created = try await driveClient.createFile(name: fileName, parentID: categoryFolderID, markdown: content)
            setEntry(DriveSyncEntry(localID: localID, driveFileID: created.id, lastSyncedAt: Date()))
        }
    }

    private func bucketKey(_ bucket: CategoryBucket) -> String {
        "category:\(bucket.projectFolderName)/\(bucket.categoryFolderName)"
    }

    private func ensureRootFolder(driveClient: GoogleDriveClient) async throws -> String {
        if let existing = entries["root"] { return existing.driveFileID }
        if let found = try await driveClient.findFile(name: Self.rootFolderName, parentID: "root", mimeType: GoogleDriveClient.folderMimeType) {
            setEntry(DriveSyncEntry(localID: "root", driveFileID: found.id, lastSyncedAt: Date()))
            return found.id
        }
        let created = try await driveClient.createFolder(name: Self.rootFolderName, parentID: nil)
        setEntry(DriveSyncEntry(localID: "root", driveFileID: created.id, lastSyncedAt: Date()))
        return created.id
    }

    private func ensureFolder(localID: String, name: String, parentID: String, driveClient: GoogleDriveClient) async throws -> String {
        if let existing = entries[localID] { return existing.driveFileID }
        if let found = try await driveClient.findFile(name: name, parentID: parentID, mimeType: GoogleDriveClient.folderMimeType) {
            setEntry(DriveSyncEntry(localID: localID, driveFileID: found.id, lastSyncedAt: Date()))
            return found.id
        }
        let created = try await driveClient.createFolder(name: name, parentID: parentID)
        setEntry(DriveSyncEntry(localID: localID, driveFileID: created.id, lastSyncedAt: Date()))
        return created.id
    }

    private func enqueuePending(_ bucket: CategoryBucket) {
        guard pending.insert(bucket).inserted else { return }
        persistIndex()
    }

    private func setEntry(_ entry: DriveSyncEntry) {
        entries[entry.localID] = entry
        persistIndex()
    }

    private func persistIndex() {
        index.save(
            entries: Array(entries.values),
            pendingBuckets: pending.map { PendingBucket(projectFolderName: $0.projectFolderName, categoryFolderName: $0.categoryFolderName) }
        )
    }
}
