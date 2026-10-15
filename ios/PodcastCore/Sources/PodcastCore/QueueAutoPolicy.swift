import Foundation

/// Android `prefEnqueueDownloaded` + `prefDeleteRemovesFromQueue` (global only; Android has no
/// per-podcast variant).
///
/// - Enqueue downloaded (default **on**): Android `DownloadServiceInterfaceImpl.getRequest` adds the
///   episode to the queue **when the download is requested** (manual and auto-download), at the
///   Enqueue location, if it is not queued yet, and tags the work `was_queued`. Cancelling that
///   download removes the queue entry again (`cancel` → `removeQueueItem` for `was_queued`).
///   A finished or failed download keeps it.
/// - Delete removes from queue (default **off**): Android `DBWriter.deleteFeedMediaOfItem` removes
///   the episode from the queue after any download delete (manual, swipe, auto-delete, cleanup).
public enum QueueAutoPolicy {
    public static let defaultEnqueueDownloaded = true
    public static let defaultDeleteRemovesFromQueue = false

    /// Value to write for a missing Enqueue downloaded key on launch. Android's default (on) only
    /// applies to new installs; an existing install updating to this version keeps its previous
    /// behaviour (off). `nil` = the key is already set, leave it alone.
    public static func migratedEnqueueDownloaded(keyPresent: Bool, hasExistingData: Bool) -> Bool? {
        if keyPresent { return nil }
        return hasExistingData ? false : defaultEnqueueDownloaded
    }

    /// Add to queue when a download is requested.
    public static func enqueueOnDownloadRequest(enabled: Bool, alreadyQueued: Bool, alreadyDownloaded: Bool) -> Bool {
        enabled && !alreadyQueued && !alreadyDownloaded
    }

    /// Remove from queue when the user cancels a download that added it.
    public static func removeOnCancel(wasQueuedByDownload: Bool, stillQueued: Bool) -> Bool {
        wasQueuedByDownload && stillQueued
    }

    /// Remove from queue when a download is deleted.
    public static func removeOnDelete(enabled: Bool, isQueued: Bool) -> Bool {
        enabled && isQueued
    }
}
