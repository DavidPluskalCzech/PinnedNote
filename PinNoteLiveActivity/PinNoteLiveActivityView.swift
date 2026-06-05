// Widget Extension target — add PinNoteActivityAttributes.swift to this target too.

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Lock-screen / notification banner view

struct PinNoteBannerView: View {
    let context: ActivityViewContext<PinNoteActivityAttributes>

    // Theme-derived colors
    private var bgColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.058, green: 0.060, blue: 0.066)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 1.0, green: 0.940, blue: 0.958)
            : .white
    }

    private var primaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.94, green: 0.92, blue: 0.86)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.55, green: 0.33, blue: 0.41)
            : Color(white: 0.08)
    }

    private var secondaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.68, green: 0.65, blue: 0.59)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.65, green: 0.48, blue: 0.53)
            : Color(white: 0.40)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(secondaryColor)

            if context.state.hasExplicitTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.custom("Noteworthy-Bold", size: 15))
                        .foregroundColor(primaryColor)
                        .lineLimit(2)

                    if !context.state.bannerBodyPreview.isEmpty {
                        Text(context.state.bannerBodyPreview)
                            .font(.custom("Noteworthy-Bold", size: 13))
                            .foregroundColor(primaryColor)
                            .lineLimit(8)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(context.state.fullPreview)
                    .font(.custom("Noteworthy-Bold", size: 13))
                    .foregroundColor(primaryColor)
                    .lineLimit(9)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(bgColor)
    }
}

// MARK: - New Note Control (iOS 18+ lock screen Controls gallery)

@available(iOS 18.0, *)
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.pinnote.control.newnote") {
            ControlWidgetButton(action: CreateNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Open PinNote and create a new note.")
    }
}

// MARK: - Widget bundle

@main
struct PinNoteLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PinNoteLiveActivityWidget()
        if #available(iOS 18.0, *) {
            NewNoteControl()
        }
    }
}

struct PinNoteLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PinNoteActivityAttributes.self) { context in
            // Lock screen / notification banner
            let bgColor = context.state.isDarkTheme
                ? Color(red: 0.058, green: 0.060, blue: 0.066)
                : (context.state.usesBlossomTheme ? Color(red: 1.0, green: 0.940, blue: 0.958) : .white)
            let primaryColor = context.state.isDarkTheme
                ? Color(red: 0.94, green: 0.92, blue: 0.86)
                : (context.state.usesBlossomTheme ? Color(red: 0.55, green: 0.33, blue: 0.41) : Color(white: 0.08))
            PinNoteBannerView(context: context)
                .activityBackgroundTint(bgColor)
                .activitySystemActionForegroundColor(primaryColor)
                .widgetURL(URL(string: "pinnote://note/\(context.attributes.noteID)"))

        } dynamicIsland: { context in
            let primaryColor = context.state.isDarkTheme
                ? Color(red: 0.94, green: 0.92, blue: 0.86)
                : (context.state.usesBlossomTheme ? Color(red: 0.55, green: 0.33, blue: 0.41) : Color(white: 0.08))
            let secondaryColor = context.state.isDarkTheme
                ? Color(red: 0.68, green: 0.65, blue: 0.59)
                : (context.state.usesBlossomTheme ? Color(red: 0.65, green: 0.48, blue: 0.53) : Color.secondary)
            return DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(primaryColor)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.title)
                            .font(.custom("Noteworthy-Bold", size: context.state.hasExplicitTitle ? 14 : 13))
                            .foregroundColor(primaryColor)
                            .lineLimit(1)
                        if !context.state.bodyPreview.isEmpty {
                            Text(context.state.bodyPreview)
                                .font(.custom("Noteworthy-Light", size: 11))
                                .foregroundColor(secondaryColor)
                                .lineLimit(2)
                        }
                    }
                }

            } compactLeading: {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(primaryColor)

            } compactTrailing: {
                Text(context.state.title.prefix(12))
                    .font(.custom("Noteworthy-Light", size: 10))
                    .foregroundColor(primaryColor)
                    .lineLimit(1)

            } minimal: {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(primaryColor)
            }
            .widgetURL(URL(string: "pinnote://note/\(context.attributes.noteID)"))
        }
    }
}
