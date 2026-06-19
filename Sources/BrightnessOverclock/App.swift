import SwiftUI
import ServiceManagement
import OverclockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = BoostState()
    private(set) lazy var engine = BoostEngine(state: state)
    let interceptor = BrightnessKeyInterceptor()
    let batterySettings = BatteryBoostSettings()
    private var batteryController: BatteryBoostController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        batteryController = BatteryBoostController(state: state, settings: batterySettings)
        batteryController?.start()
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
        batteryController?.stop()
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
            MenuView(
                state: appDelegate.state,
                batterySettings: appDelegate.batterySettings,
                onEnableKeys: { appDelegate.interceptor.start() }
            )
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
    @ObservedObject var batterySettings: BatteryBoostSettings
    let onEnableKeys: () -> Void
    @State private var accessibilityGranted =
        BrightnessKeyInterceptor.hasAccessibilityPermission(prompt: false)

    var body: some View {
        Toggle("Overclock brightness", isOn: Binding(
            get: { state.isBoosted },
            set: { $0 ? state.toggleOn() : state.toggleOff() }
        ))
        .disabled(!state.isBoostAllowed)
        BoostLevelPicker(state: state)
        Text(state.isBoosted
             ? "≈ \(BoostMath.approximateNits(level: state.boostLevel)) nits"
             : "Normal (≤ \(Int(BoostMath.sdrReferenceNits)) nits)")
        if let reason = state.boostBlockReason {
            Text(reason)
        }
        if !accessibilityGranted {
            Divider()
            Button("Enable brightness keys…") {
                _ = BrightnessKeyInterceptor.hasAccessibilityPermission(prompt: true)
                onEnableKeys()
            }
        }
        Divider()
        BatterySettingsView(settings: batterySettings)
        LaunchAtLoginToggle()
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

struct BoostLevelPicker: View {
    @ObservedObject var state: BoostState

    var body: some View {
        Picker("Overclock level", selection: Binding(
            get: { state.currentBoostStep },
            set: { step in
                step == 0 ? state.toggleOff() : state.setBoostStep(step)
            }
        )) {
            Text("Off").tag(0)
            ForEach(1...state.boostStepCount, id: \.self) { step in
                Text("Step \(step) (≈ \(state.approximateNits(forBoostStep: step)) nits)").tag(step)
            }
        }
        .disabled(!state.isBoostAllowed)
    }
}

struct BatterySettingsView: View {
    @ObservedObject var settings: BatteryBoostSettings

    var body: some View {
        Text(settings.currentStatus.menuDescription)
        Picker("Boost on battery", selection: $settings.policy) {
            ForEach(BatteryBoostPolicy.allCases) { policy in
                Text(policy.displayName).tag(policy)
            }
        }
        if settings.policy == .disableBelowPercentage {
            Picker(
                "Turn off below",
                selection: Binding(
                    get: { settings.minimumBatteryPercentage },
                    set: { settings.setMinimumBatteryPercentage($0) }
                )
            ) {
                ForEach(BatteryBoostSettings.allowedMinimumBatteryPercentages, id: \.self) { percentage in
                    Text("\(percentage)%").tag(percentage)
                }
            }
        }
        Divider()
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
