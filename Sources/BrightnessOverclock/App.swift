import SwiftUI
import ServiceManagement
import OverclockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = BoostState()
    private(set) lazy var engine = BoostEngine(state: state)
    let interceptor = BrightnessKeyInterceptor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.applyPersisted()
        registerLoginItemOnFirstLaunch()
        interceptor.boostLevelProvider = { [weak self] in self?.state.boostLevel ?? 1.0 }
        interceptor.onStepUp = { [weak self] in self?.state.stepUp() }
        interceptor.onStepDown = { [weak self] in self?.state.stepDown() }
        if BrightnessKeyInterceptor.hasAccessibilityPermission(prompt: false) {
            interceptor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }

    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }
}

@main
struct BrightnessOverclockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appDelegate.state, onEnableKeys: {
                appDelegate.interceptor.start()
            })
        } label: {
            MenuBarIcon(state: appDelegate.state)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarIcon: View {
    @ObservedObject var state: BoostState

    var body: some View {
        if state.isBoosted {
            Image(systemName: "sun.max.fill")
            Text("\(BoostMath.approximateNits(level: state.boostLevel))")
        } else {
            Image(systemName: "sun.max")
        }
    }
}

struct MenuView: View {
    @ObservedObject var state: BoostState
    let onEnableKeys: () -> Void
    @State private var accessibilityGranted =
        BrightnessKeyInterceptor.hasAccessibilityPermission(prompt: false)

    var body: some View {
        Toggle("Overclock brightness", isOn: Binding(
            get: { state.isBoosted },
            set: { $0 ? state.toggleOn() : state.toggleOff() }
        ))
        Text(state.isBoosted
             ? "≈ \(BoostMath.approximateNits(level: state.boostLevel)) nits"
             : "Normal (≤ \(Int(BoostMath.sdrReferenceNits)) nits)")
        if !accessibilityGranted {
            Divider()
            Button("Enable brightness keys…") {
                _ = BrightnessKeyInterceptor.hasAccessibilityPermission(prompt: true)
                onEnableKeys()
            }
        }
        Divider()
        LaunchAtLoginToggle()
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = newValue
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        ))
    }
}
