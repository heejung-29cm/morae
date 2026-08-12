import AppKit
import ImageIO
import SwiftUI

@MainActor
@main
struct MoraeApp: App {
    @NSApplicationDelegateAdaptor(MoraeApplicationDelegate.self)
    private var applicationDelegate

    private let container: AppContainer
    private let settingsWindowController: MoraeSettingsWindowController
    private let onboardingWindowController: MoraeOnboardingWindowController

    init() {
        let container = AppContainer.live()
        self.container = container
        settingsWindowController = MoraeSettingsWindowController(
            container: container
        )
        onboardingWindowController = MoraeOnboardingWindowController(
            container: container
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(
                container: container,
                openSettings: settingsWindowController.show
            )
        } label: {
            HamsterMenuBarIcon(
                isAnimating: container.agentActivity?
                    .shouldAnimateMenuBarIcon == true
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MoraeSettingsWindowController: NSWindowController,
    NSWindowDelegate
{
    static let title = "모래 설정"
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary,
    ]

    init(container: AppContainer) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = container.runtimeProfile.isFreshTest
            ? "\(Self.title) · 테스트"
            : Self.title
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView(container: container)
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior = Self.collectionBehavior
        window.hidesOnDeactivate = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.collectionBehavior = Self.collectionBehavior
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct HamsterMenuBarIcon: View {
    static let restingFrameNumber = 6
    static let frameDuration = 0.09
    static let canvasSize = 14.0
    static let glyphSize = 14.0
    static let frames = loadFrames()

    let isAnimating: Bool
    @State private var frameIndex = restingFrameNumber - 1

    var body: some View {
        ZStack {
            Color.clear
                .frame(
                    width: Self.canvasSize,
                    height: Self.canvasSize
                )

            if let frame = Self.frames[safe: frameIndex] {
                Image(nsImage: frame)
                    .renderingMode(.original)
                    .interpolation(.none)
                    .frame(
                        width: Self.glyphSize,
                        height: Self.glyphSize
                    )
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: Self.glyphSize))
            }
        }
        .frame(width: Self.canvasSize, height: Self.canvasSize)
        .task(id: isAnimating) {
            frameIndex = Self.restingFrameNumber - 1
            guard isAnimating, !Self.frames.isEmpty else { return }

            var nextIndex = 0
            while !Task.isCancelled {
                frameIndex = nextIndex
                nextIndex = (nextIndex + 1) % Self.frames.count
                try? await Task.sleep(
                    for: .seconds(Self.frameDuration)
                )
            }
        }
        .accessibilityLabel("모래")
    }

    static func frame(at date: Date, animated: Bool) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        let index: Int
        if animated {
            index = Int(
                date.timeIntervalSinceReferenceDate / frameDuration
            ) % frames.count
        } else {
            index = min(restingFrameNumber - 1, frames.count - 1)
        }
        return frames[index]
    }

    private static func loadFrames() -> [NSImage] {
        guard let asset = NSDataAsset(name: "HamsterDance"),
              let source = CGImageSourceCreateWithData(
                asset.data as CFData,
                nil
              )
        else {
            return []
        }

        return (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let image = CGImageSourceCreateImageAtIndex(
                source,
                index,
                nil
            ) else {
                return nil
            }
            let frame = NSImage(
                cgImage: image,
                size: NSSize(
                    width: Self.glyphSize,
                    height: Self.glyphSize
                )
            )
            frame.isTemplate = false
            return frame
        }
    }
}

@MainActor
final class MoraeApplicationDelegate: NSObject, NSApplicationDelegate {
    static let quitMenuTitle = "Morae 종료"

    private var rightMouseDownMonitor: Any?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        rightMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDown
        ) { [weak self] event in
            guard let self,
                  Self.containsStatusBarButton(
                    in: event.window?.contentView
                  )
            else {
                return event
            }

            self.showQuitMenu(for: event)
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let rightMouseDownMonitor {
            NSEvent.removeMonitor(rightMouseDownMonitor)
        }
        MoraeRuntimeProfile.current().cleanUp()
    }

    static func containsStatusBarButton(in view: NSView?) -> Bool {
        guard let view else { return false }
        if view is NSStatusBarButton {
            return true
        }
        return view.subviews.contains {
            containsStatusBarButton(in: $0)
        }
    }

    private func showQuitMenu(for event: NSEvent) {
        guard let contentView = event.window?.contentView else { return }

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: Self.quitMenuTitle,
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
