import SwiftUI

struct OnboardingView: View {
  let controller: AppController

  var body: some View {
    VStack(spacing: 20) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
      Text("Welcome to AetherSeek")
        .font(.largeTitle.weight(.semibold))
      Text("Press \(controller.settings.launcherHotKey.displayString) to search apps, type “snip” for snippets and “tr” to translate.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)

      GroupBox {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: controller.isAccessibilityGranted ? "checkmark.seal.fill" : "hand.raised.fill")
            .font(.title)
            .foregroundStyle(controller.isAccessibilityGranted ? .green : .orange)
          VStack(alignment: .leading, spacing: 6) {
            Text("Accessibility").font(.headline)
            Text("AetherSeek needs Accessibility access to expand snippets as you type and to paste into other apps. Nothing you type leaves your Mac.")
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if !controller.isAccessibilityGranted {
              Button("Grant Access…", action: controller.requestAccessibility)
                .buttonStyle(.glassProminent)
                .padding(.top, 4)
            }
          }
          Spacer(minLength: 0)
        }
        .padding(8)
      }

      HStack {
        Button("Open Settings") { controller.showSettings() }
        Spacer()
        Button(controller.isAccessibilityGranted ? String(localized: "Done") : String(localized: "Later")) {
          controller.finishOnboarding()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(32)
    .frame(width: 520)
  }
}
