import AppKit
import SwiftUI

/// Live permission state for the window: polled once a second while it is
/// open, so a toggle flipped in System Settings shows up without a click.
final class PermissionsModel: ObservableObject {
    @Published var status: PermissionStatus
    @Published var resetMessage: String?

    init(status: PermissionStatus) {
        self.status = status
    }
}

struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    let isBundled: Bool
    let onRequest: (Permission) -> Void
    let onRelaunch: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(spacing: 10) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    row(permission)
                }
            }
            footer
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.status.allGranted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.status.allGranted ? Color.green : Theme.attention)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.status.allGranted ? "MacToys is ready" : "MacToys needs two permissions")
                    .font(Theme.title(17))
                Text(subtitle)
                    .font(Theme.body(12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        switch (isBundled, model.status.allGranted) {
        case (true, false): "Grant each one in System Settings. Everything stays on your Mac."
        case (true, true): "Every module can work. You can close this window."
        case (false, false): "Running from source: grant these to your terminal app (Terminal, iTerm…), not to MacToys."
        case (false, true): "Running from source: your terminal app holds these permissions."
        }
    }

    private func row(_ permission: Permission) -> some View {
        let granted = model.status.isGranted(permission)
        return HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(Theme.title(13))
                Text(permission.reason)
                    .font(Theme.body(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(Theme.caption(11.5))
                    .foregroundStyle(.green)
            } else {
                Button("Grant…") { onRequest(permission) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent) // brand, not the system accent (red reads as an error)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 0.5)
        )
        .animation(Theme.Motion.selection, value: granted)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.status.screenRecording {
                Label("macOS applies Screen Recording after MacToys restarts.", systemImage: "arrow.clockwise")
                    .font(Theme.body(11.5))
                    .foregroundStyle(.secondary)
            }
            if let message = model.resetMessage {
                Text(message)
                    .font(Theme.body(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isBundled {
                    Button("Reset Permissions…", action: onReset)
                        .help("Use when a permission shows ON in System Settings but MacToys still cannot use it.")
                }
                Spacer()
                if isBundled && !model.status.allGranted {
                    Button("Relaunch MacToys", action: onRelaunch)
                }
                Button(model.status.allGranted ? "Done" : "Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One shared Permissions window: opened at launch when something is missing
/// and from the status menu at any time.
@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionsWindowController()

    private var window: NSWindow?
    private var model: PermissionsModel?
    private var poll: Timer?

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = PermissionsModel(status: Permissions.current)
        self.model = model
        let view = PermissionsView(
            model: model,
            isBundled: Permissions.isBundled,
            onRequest: { Permissions.request($0) },
            onRelaunch: { Permissions.relaunch() },
            onReset: { [weak self] in self?.confirmReset() },
            onDone: { [weak self] in self?.window?.close() }
        )
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacToys Permissions"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        window.center()
        self.window = window

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionsWindowController.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        guard let model else { return }
        let status = Permissions.current
        if status != model.status { model.status = status }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset MacToys' permissions?"
        alert.informativeText = """
        macOS forgets the Screen Recording and Accessibility grants of MacToys only. \
        Then grant them again here and relaunch. Use this when a switch is ON in \
        System Settings but MacToys still cannot use it — common after an update.
        """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ok = Permissions.resetGrants()
        model?.resetMessage = ok
            ? "Reset done. Grant both permissions again, then relaunch MacToys."
            : "Could not reset automatically. Remove MacToys from both lists in System Settings → Privacy & Security, then grant again."
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
        window = nil
        model = nil
    }
}
