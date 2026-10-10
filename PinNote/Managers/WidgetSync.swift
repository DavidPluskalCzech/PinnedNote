import Combine
import Foundation
import WidgetKit

/// Keeps the home-screen widget current: whenever the notes, theme or font change,
/// writes the latest notes for it and asks it to reload.
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        NoteStore.shared.$notes
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        for name in [Notification.Name.pnThemeChanged, .pnFontChanged] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in self?.update() }
                .store(in: &cancellables)
        }
        update()
    }

    private func update() {
        let notes = NoteStore.shared.notes
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(WidgetNotesSnapshot.maxNotes)
            .map { note in
                WidgetNote(
                    id: note.id,
                    title: note.displayTitle,
                    hasTitle: !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    body: note.previewBody(maxLines: 6),
                    isPinned: note.isPinned
                )
            }
        WidgetNotesSnapshot(
            notes: Array(notes),
            themeRawValue: ThemeManager.shared.current.rawValue,
            fontRawValue: ThemeManager.shared.font.rawValue
        ).save()
        WidgetCenter.shared.reloadTimelines(ofKind: "PinNoteNotesWidget")
    }
}
