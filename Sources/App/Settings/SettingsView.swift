import AetherSeekCore
import AppKit
import SwiftUI

struct SettingsView: View {
  let controller: AppController

  var body: some View {
    TabView {
      Tab("General", systemImage: "gearshape") {
        GeneralSettings(controller: controller)
      }
      Tab("Snippets", systemImage: "text.quote") {
        SnippetSettings(controller: controller, library: controller.snippets)
      }
    }
    .frame(width: 880, height: 600)
  }
}

struct GeneralSettings: View {
  let controller: AppController
  @State private var launchesAtLogin = false

  var body: some View {
    @Bindable var settings = controller.settings
    Form {
      Section("Shortcuts") {
        LabeledContent("Show AetherSeek") {
          HStack {
            if controller.hotKeyConflicts.contains(.launcher) { conflictBadge }
            KeyRecorder(combo: $settings.launcherHotKey, onRecordingChange: controller.setRecordingHotKey)
          }
        }
        LabeledContent("Show snippet viewer") {
          HStack {
            if controller.hotKeyConflicts.contains(.snippetViewer) { conflictBadge }
            KeyRecorder(combo: $settings.snippetViewerHotKey, onRecordingChange: controller.setRecordingHotKey)
          }
        }
      }
      Section {
        Toggle("Launch at login", isOn: $launchesAtLogin)
          .onChange(of: launchesAtLogin) { controller.launchesAtLogin = launchesAtLogin }
      }
      Section("Permissions") {
        LabeledContent("Accessibility") {
          if controller.isAccessibilityGranted {
            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
          } else {
            Button("Open System Settings", action: controller.openAccessibilitySettings)
          }
        }
        Text("Needed to expand snippets as you type and to paste into other apps.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Keywords") {
        LabeledContent {
          Text("Search snippets in the launcher")
        } label: {
          Text(verbatim: "snip").monospaced()
        }
        LabeledContent {
          Text("Translate on device")
        } label: {
          Text(verbatim: "tr").monospaced()
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { launchesAtLogin = controller.launchesAtLogin }
    .onChange(of: controller.settings.launcherHotKey) { controller.applyHotKeys() }
    .onChange(of: controller.settings.snippetViewerHotKey) { controller.applyHotKeys() }
  }

  private var conflictBadge: some View {
    Label("In use by another app", systemImage: "exclamationmark.triangle.fill")
      .foregroundStyle(.orange)
      .font(.caption)
  }
}

struct SnippetSettings: View {
  let controller: AppController
  let library: SnippetLibrary
  @State private var selectedGroup: UUID?
  @State private var importMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      HSplitView {
        groupList.frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
        Group {
          if let id = selectedGroup, let group = library.groups.first(where: { $0.id == id }) {
            SnippetGroupEditor(library: library, group: group).id(group.id)
          } else {
            ContentUnavailableView("No Group Selected", systemImage: "text.quote", description: Text("Create a group or import from Alfred."))
          }
        }
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      footer
    }
    .onAppear { selectedGroup = selectedGroup ?? library.groups.first?.id }
    .alert(importMessage ?? "", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
      Button("OK") {}
    }
  }

  private var groupList: some View {
    List(selection: $selectedGroup) {
      ForEach(library.groups) { group in
        HStack {
          Text(group.name)
          Spacer()
          Text(group.prefix).monospaced().foregroundStyle(.secondary)
        }
        .opacity(group.isEnabled ? 1 : 0.45)
        .tag(group.id)
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Button {
          let group = SnippetGroup(name: String(localized: "New Group"))
          library.save(group)
          selectedGroup = group.id
        } label: { Image(systemName: "plus") }
        Button {
          guard let id = selectedGroup, let group = library.groups.first(where: { $0.id == id }) else { return }
          guard confirm(String(localized: "Delete “\(group.name)” and its \(group.snippets.count) snippets?")) else { return }
          library.delete(group)
          selectedGroup = library.groups.first?.id
        } label: { Image(systemName: "minus") }
        .disabled(selectedGroup == nil)
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
  }

  private var footer: some View {
    HStack(spacing: 16) {
      Picker("Storage", selection: Binding(get: { controller.settings.snippetLocation }, set: { controller.changeSnippetLocation($0) })) {
        Text("This Mac").tag(AppSettings.SnippetLocation.local)
        Text("iCloud Drive").tag(AppSettings.SnippetLocation.iCloud)
      }
      .fixedSize()
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([library.store.directory])
      }
      Spacer()
      if let error = library.lastError {
        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(1)
      }
      Toggle("Expand as I type", isOn: Binding(
        get: { controller.settings.autoExpansionEnabled },
        set: { controller.settings.autoExpansionEnabled = $0; controller.applyExpansionSettings() }))
      Button("Import from Alfred…", action: importAlfred)
    }
    .padding(12)
  }

  private func importAlfred() {
    let panel = NSOpenPanel()
    panel.message = String(localized: "Choose Alfred.alfredpreferences")
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = AlfredSnippetImporter.defaultPreferences.deletingLastPathComponent()
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let count = library.importAlfred(from: url)
    importMessage = library.lastError ?? String(localized: "Imported \(count) snippets.")
    selectedGroup = selectedGroup ?? library.groups.first?.id
  }
}

@MainActor
func confirm(_ message: String) -> Bool {
  let alert = NSAlert()
  alert.messageText = message
  alert.addButton(withTitle: String(localized: "Delete"))
  alert.addButton(withTitle: String(localized: "Cancel"))
  alert.buttons[0].hasDestructiveAction = true
  return alert.runModal() == .alertFirstButtonReturn
}
