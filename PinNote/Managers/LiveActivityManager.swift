import ActivityKit
import Foundation
import UIKit

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var activity: Activity<PinNoteActivityAttributes>?
    private var operationID = 0

    private init() {
        // Restore any activity that was running before the app was killed.
        // Without this, `activity` would be nil on every cold start and
        // Activity.request() would be called again — potentially showing
        // the permission prompt a second time.
        refreshCachedActivity()
        reconcileRestoredActivity()

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .pnThemeChanged, object: nil
        )
    }

    private func refreshCachedActivity(preferredNoteID: String? = nil) {
        let activities = Activity<PinNoteActivityAttributes>.activities
        if let preferredNoteID,
           let preferred = activities.first(where: { $0.attributes.noteID == preferredNoteID }) {
            activity = preferred
        } else if let activity,
                  activities.contains(where: { $0.id == activity.id }) {
            return
        } else {
            activity = activities.first
        }
    }

    private func reconcileRestoredActivity() {
        guard let pinnedNote = NoteStore.shared.notes.first(where: { $0.isPinned }) else {
            stop()
            return
        }

        refreshCachedActivity(preferredNoteID: pinnedNote.id.uuidString)

        guard let activity else {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.refreshCachedActivity(preferredNoteID: pinnedNote.id.uuidString)
                    guard self.activity == nil,
                          let freshPinnedNote = NoteStore.shared.notes.first(where: { $0.id == pinnedNote.id }),
                          freshPinnedNote.isPinned else { return }
                    NoteStore.shared.updatePinOnly(self.unpinned(freshPinnedNote))
                }
            }
            return
        }

        if activity.attributes.noteID != pinnedNote.id.uuidString {
            update(with: pinnedNote)
        }
        Task { await monitorDismissal(activity: activity, noteID: pinnedNote.id) }
    }

    func reconcileCurrentState() {
        refreshCachedActivity()
        reconcileRestoredActivity()
    }

    private func unpinned(_ note: Note) -> Note {
        var note = note
        note.isPinned = false
        return note
    }

    @objc private func themeChanged() {
        guard let pinnedNote = NoteStore.shared.notes.first(where: { $0.isPinned }) else { return }
        update(with: pinnedNote)
    }

    // MARK: - Start

    func start(with note: Note) async -> Bool {
        operationID += 1
        let currentOperationID = operationID

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        let noteID = note.id.uuidString
        refreshCachedActivity(preferredNoteID: noteID)

        if let existing = Activity<PinNoteActivityAttributes>.activities.first(where: { $0.attributes.noteID == noteID }) {
            activity = existing
            update(with: note)
            Task { await monitorDismissal(activity: existing, noteID: note.id) }
            return true
        }

        let existingActivities = Activity<PinNoteActivityAttributes>.activities
        for existing in existingActivities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        if let activity, !existingActivities.contains(where: { $0.id == activity.id }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard currentOperationID == operationID else { return false }
        activity = nil

        if !existingActivities.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return await requestActivityWithRetry(with: note, operationID: currentOperationID)
    }

    private func requestActivityWithRetry(with note: Note, operationID: Int) async -> Bool {
        let delays: [UInt64] = [0, 200_000_000, 450_000_000]

        for delay in delays {
            guard operationID == self.operationID else { return false }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            let noteID = note.id.uuidString
            if let existing = Activity<PinNoteActivityAttributes>.activities.first(where: { $0.attributes.noteID == noteID }) {
                activity = existing
                update(with: note)
                Task { await monitorDismissal(activity: existing, noteID: note.id) }
                return true
            }

            if requestActivity(with: note) {
                return true
            }
        }

        return false
    }

    private func requestActivity(with note: Note) -> Bool {
        let attributes = PinNoteActivityAttributes(noteID: note.id.uuidString)
        let state      = PinNoteActivityAttributes.ContentState(
            noteTitle:        note.title,
            content:          note.content,
            modifiedAt:       note.modifiedAt,
            isBlossomTheme:   ThemeManager.shared.current == .blossom,
            themeRawValue:    ThemeManager.shared.current.rawValue
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity<PinNoteActivityAttributes>.request(
                attributes: attributes,
                content:    content,
                pushType:   nil
            )
            if let activity {
                Task { await monitorDismissal(activity: activity, noteID: note.id) }
            }
            return true
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
            activity = nil
            return false
        }
    }

    // MARK: - Dismissal monitor

    /// Watches for the user swiping away the Live Activity from the lock screen,
    /// and unpins the note in the store when that happens.
    private func monitorDismissal(activity: Activity<PinNoteActivityAttributes>, noteID: UUID) async {
        for await state in activity.activityStateUpdates {
            guard state == .dismissed || state == .ended else { continue }
            await MainActor.run {
                guard self.activity?.id == activity.id else { return }
                guard var note = NoteStore.shared.notes.first(where: { $0.id == noteID }),
                      note.isPinned else { return }
                note.isPinned = false
                NoteStore.shared.updatePinOnly(note)
                self.activity = nil
            }
            break
        }
    }

    // MARK: - Update

    func update(with note: Note) {
        refreshCachedActivity(preferredNoteID: note.id.uuidString)
        guard let activity,
              activity.attributes.noteID == note.id.uuidString
        else { return }

        let state = PinNoteActivityAttributes.ContentState(
            noteTitle:      note.title,
            content:        note.content,
            modifiedAt:     note.modifiedAt,
            isBlossomTheme: ThemeManager.shared.current == .blossom,
            themeRawValue:  ThemeManager.shared.current.rawValue
        )
        let content = ActivityContent(state: state, staleDate: nil)
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "UpdatePinnedNote") {}
        Task {
            await activity.update(content)
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }

    // MARK: - Stop

    func stop() {
        operationID += 1
        let activitiesToEnd = Activity<PinNoteActivityAttributes>.activities
        Task {
            for a in activitiesToEnd {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        activity = nil
    }
}
