import Combine
import Foundation
import UserNotifications

@MainActor
final class ScheduledPinManager {
    static let shared = ScheduledPinManager()

    private let notificationPrefix = "scheduled-pin-"
    private var timer: Timer?
    private var isProcessingDuePins = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NoteStore.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSchedule()
            }
            .store(in: &cancellables)
    }

    func start() {
        refreshSchedule()
        Task { await processDuePins() }
    }

    func refreshSchedule() {
        timer?.invalidate()
        timer = nil
        clearScheduledPinsBlockedByPaywall()

        let now = Date()
        guard let nextDate = NoteStore.shared.notes
            .compactMap(\.scheduledPinDate)
            .filter({ $0 > now })
            .min()
        else { return }

        let interval = max(nextDate.timeIntervalSince(now), 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.processDuePins()
            }
        }
    }

    func scheduleNotificationBackupIfPossible(for note: Note) {
        guard let date = note.scheduledPinDate, date > Date() else { return }
        guard PurchaseManager.shared.allowsProFeatures(at: date) else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self?.scheduleNotificationBackup(for: note, at: date)
            }
        }
    }

    func removeNotificationBackup(noteID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: noteID)]
        )
    }

    func processDuePins() async {
        guard !isProcessingDuePins else { return }
        isProcessingDuePins = true
        defer {
            isProcessingDuePins = false
            refreshSchedule()
        }

        let now = Date()
        let dueNotes = NoteStore.shared.notes
            .filter { ($0.scheduledPinDate ?? .distantFuture) <= now }
            .sorted { ($0.scheduledPinDate ?? .distantPast) < ($1.scheduledPinDate ?? .distantPast) }

        guard !dueNotes.isEmpty else { return }

        for note in dueNotes {
            NoteStore.shared.updateScheduledPinDate(noteID: note.id, date: nil)
            removeNotificationBackup(noteID: note.id)
        }
    }

    func processScheduledPin(noteID: UUID) async {
        guard let note = NoteStore.shared.notes.first(where: { $0.id == noteID }),
              let scheduledDate = note.scheduledPinDate,
              scheduledDate <= Date()
        else {
            await processDuePins()
            return
        }

        NoteStore.shared.updateScheduledPinDate(noteID: note.id, date: nil)
        removeNotificationBackup(noteID: note.id)
    }

    private func scheduleNotificationBackup(for note: Note, at date: Date) {
        let noteID = note.id
        let content = UNMutableNotificationContent()
        content.body = notificationText(for: note)
        content.sound = .default
        content.userInfo = ["noteID": noteID.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: noteID),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: noteID)]
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notificationIdentifier(for noteID: UUID) -> String {
        "\(notificationPrefix)\(noteID.uuidString)"
    }

    private func clearScheduledPinsBlockedByPaywall() {
        let purchaseManager = PurchaseManager.shared
        guard !purchaseManager.isPro else { return }

        for note in NoteStore.shared.notes {
            guard let scheduledDate = note.scheduledPinDate,
                  !purchaseManager.allowsProFeatures(at: scheduledDate)
            else { continue }

            NoteStore.shared.updateScheduledPinDate(noteID: note.id, date: nil)
            removeNotificationBackup(noteID: note.id)
        }
    }

    private func notificationText(for note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty {
            return content
        }
        if content.isEmpty {
            return title
        }
        return "\(title)\n\(content)"
    }
}
