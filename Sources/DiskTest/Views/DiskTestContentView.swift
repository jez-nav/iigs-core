import IIGSCore
import SwiftUI
import UniformTypeIdentifiers

struct DiskTestContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: DiskTestEmulatorStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                displayArea

                Divider()

                diskPanel
                    .frame(width: 330)
            }

            keyboardControlBar
        }
        .background(Color.black.ignoresSafeArea())
        .background(WindowTitleUpdater(title: store.windowTitle))
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.appBecameActive()
            case .inactive, .background:
                store.appBecameInactive()
            @unknown default:
                store.appBecameInactive()
            }
        }
    }

    private var displayArea: some View {
        ZStack {
            Color.black

            DiskTestVideoSurfaceView(
                frame: store.videoFrame,
                isFocused: store.displayHasKeyboardFocus,
                onFocusChanged: store.setDisplayFocus(_:),
                onMouse: store.handleMouse(displayX:displayY:buttonDown:syncToHostPosition:),
                onMouseExit: store.handleMouseExit,
                onKeyEvent: store.handleKeyEvent(_:)
            )
            .aspectRatio(displayAspectRatio(for: store.videoFrame), contentMode: .fit)
            .padding(24)

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Disks", systemImage: "externaldrive.connected.to.line.below")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(DiskTestMountOption.allCases) { option in
                        diskRow(option)

                        if option != DiskTestMountOption.allCases.last {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
            }

            Divider()

            audioPanel

            Divider()

            batteryRAMPanel

            Divider()

            Text(store.diskStatus)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(14)
        }
        .background(.regularMaterial)
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Audio", systemImage: store.audioMuted ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(.subheadline, weight: .semibold))

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { !store.audioMuted },
                        set: { store.setAudioEnabled($0) }
                    )
                )
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Slider(
                    value: Binding(
                        get: { store.audioVolume },
                        set: { store.setAudioVolume($0) }
                    ),
                    in: 0...1
                )
                .disabled(store.audioMuted)
            }

            Text(store.audioStatus)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
    }

    private var batteryRAMPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Battery RAM", systemImage: "memorychip")
                    .font(.system(.subheadline, weight: .semibold))

                Spacer()

                Text(batteryRAMProfileText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Picker("Startup", selection: settingsByteBinding(\.startupSlot, mask: 0x07)) {
                    Text("Scan").tag(0)
                    ForEach(1...7, id: \.self) { slot in
                        Text("Slot \(slot)").tag(slot)
                    }
                }
                .pickerStyle(.menu)

                Toggle(
                    "Visit Monitor",
                    isOn: Binding(
                        get: { store.batteryRAMSettings.visitMonitorCDAEnabled },
                        set: { enabled in
                            updateBatteryRAMSettings { $0.visitMonitorCDAEnabled = enabled }
                        }
                    )
                )
                .disabled(store.batteryRAMProfile != .rom03)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Slider(
                    value: Binding(
                        get: { Double(store.batteryRAMSettings.userVolume & 0x0F) },
                        set: { value in
                            updateBatteryRAMSettings { $0.userVolume = UInt8(value.rounded()) & 0x0F }
                        }
                    ),
                    in: 0...15,
                    step: 1
                )

                Text("\(Int(store.batteryRAMSettings.userVolume & 0x0F))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
            }

            HStack(spacing: 8) {
                colorPicker("Text", selection: settingsByteBinding(\.textColor, mask: 0x0F))
                colorPicker("Back", selection: settingsByteBinding(\.backgroundColor, mask: 0x0F))
                colorPicker("Border", selection: settingsByteBinding(\.borderColor, mask: 0x0F))
            }

            HStack(spacing: 8) {
                slotPicker("S5", selection: settingsByteBinding(\.slot5, mask: 0x01))
                slotPicker("S6", selection: settingsByteBinding(\.slot6, mask: 0x01))
                slotPicker("S7", selection: settingsByteBinding(\.slot7, mask: 0x01))
            }

            HStack(spacing: 6) {
                Image(systemName: store.batteryRAMChecksumIsValid ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(store.batteryRAMChecksumIsValid ? Color.green : Color.orange)
                    .frame(width: 18)

                Text(store.batteryRAMChecksumIsValid ? "Checksum OK" : "Checksum Invalid")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(14)
    }

    private func diskRow(_ option: DiskTestMountOption) -> some View {
        let info = store.mountedDisks[option.target]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: option.systemImage)
                    .foregroundStyle(info == nil ? Color.secondary : Color.green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)

                    Text(info?.name ?? "Empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(option.target.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let info {
                Text(info.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                Button {
                    store.chooseDisk(for: option.target)
                } label: {
                    Label("Mount", systemImage: "externaldrive.badge.plus")
                }

                Button {
                    store.ejectDisk(target: option.target)
                } label: {
                    Label("Eject", systemImage: "eject")
                }
                .disabled(info == nil)
            }
            .controlSize(.small)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            store.handleDrop(providers, target: option.target)
        }
    }

    private var keyboardControlBar: some View {
        HStack(spacing: 12) {
            Button(action: store.sendColdReset) {
                Label("Cold Reset", systemImage: "power")
            }

            Button(action: store.sendWarmReset) {
                Label("Warm Reset", systemImage: "restart")
            }

            Button(action: store.sendControlResetKey) {
                Label("Control-Reset", systemImage: "keyboard.badge.ellipsis")
            }

            Button(action: store.sendControlPanelResetKey) {
                Label("Control Panel", systemImage: "gearshape")
            }

            Button(action: store.sendClassicDeskAccessoryKey) {
                Label("Desk Accessory", systemImage: "menubar.rectangle")
            }

            Button(action: store.typeBasicSmokeTest) {
                Label("Type BASIC Test", systemImage: "keyboard")
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 8)

            Text(store.inputStatus)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(store.displayHasKeyboardFocus ? .green : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func displayAspectRatio(for frame: IIGSVideoFrame) -> CGFloat {
        let superHiresFrameWidth = IIGSVideoRenderer.superHiresWidth + IIGSVideoRenderer.wideBorderX * 2
        let superHiresFrameHeight = IIGSVideoRenderer.superHiresHeight + IIGSVideoRenderer.superHiresBorderY * 2
        if frame.width == IIGSVideoRenderer.superHiresWidth && frame.height == IIGSVideoRenderer.superHiresHeight
            || frame.width == superHiresFrameWidth && frame.height == superHiresFrameHeight {
            return CGFloat(frame.width) / CGFloat(frame.height * 2)
        }
        return CGFloat(max(1, frame.width)) / CGFloat(max(1, frame.height))
    }

    private var batteryRAMProfileText: String {
        switch store.batteryRAMProfile {
        case .rom01:
            "ROM 01"
        case .rom03:
            "ROM 03"
        }
    }

    private func updateBatteryRAMSettings(_ update: (inout IIGSBatteryRAMSettings) -> Void) {
        var settings = store.batteryRAMSettings
        update(&settings)
        store.setBatteryRAMSettings(settings)
    }

    private func settingsByteBinding(
        _ keyPath: WritableKeyPath<IIGSBatteryRAMSettings, UInt8>,
        mask: UInt8
    ) -> Binding<Int> {
        Binding(
            get: { Int(store.batteryRAMSettings[keyPath: keyPath] & mask) },
            set: { value in
                updateBatteryRAMSettings { settings in
                    settings[keyPath: keyPath] = UInt8(value) & mask
                }
            }
        )
    }

    private func colorPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(iigsControlPanelColors) { option in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(option.color)
                        .frame(width: 12, height: 12)

                    Text(option.name)
                }
                .tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }

    private func slotPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("Internal").tag(0)
            Text("Your Card").tag(1)
        }
        .pickerStyle(.menu)
    }
}

private struct IIGSControlPanelColor: Identifiable {
    let id: Int
    let name: String
    let color: Color
}

private let iigsControlPanelColors = [
    IIGSControlPanelColor(id: 0x0, name: "Black", color: Color(red: 0.05, green: 0.05, blue: 0.05)),
    IIGSControlPanelColor(id: 0x1, name: "Deep Red", color: Color(red: 0.72, green: 0.08, blue: 0.08)),
    IIGSControlPanelColor(id: 0x2, name: "Dark Blue", color: Color(red: 0.18, green: 0.18, blue: 0.72)),
    IIGSControlPanelColor(id: 0x3, name: "Purple", color: Color(red: 0.72, green: 0.18, blue: 0.72)),
    IIGSControlPanelColor(id: 0x4, name: "Dark Green", color: Color(red: 0.08, green: 0.48, blue: 0.08)),
    IIGSControlPanelColor(id: 0x5, name: "Gray", color: Color(red: 0.48, green: 0.48, blue: 0.48)),
    IIGSControlPanelColor(id: 0x6, name: "Medium Blue", color: Color(red: 0.18, green: 0.48, blue: 0.92)),
    IIGSControlPanelColor(id: 0x7, name: "Light Blue", color: Color(red: 0.62, green: 0.78, blue: 1.00)),
    IIGSControlPanelColor(id: 0x8, name: "Brown", color: Color(red: 0.48, green: 0.26, blue: 0.08)),
    IIGSControlPanelColor(id: 0x9, name: "Orange", color: Color(red: 0.92, green: 0.48, blue: 0.08)),
    IIGSControlPanelColor(id: 0xA, name: "Light Gray", color: Color(red: 0.72, green: 0.72, blue: 0.72)),
    IIGSControlPanelColor(id: 0xB, name: "Pink", color: Color(red: 1.00, green: 0.62, blue: 0.72)),
    IIGSControlPanelColor(id: 0xC, name: "Green", color: Color(red: 0.08, green: 0.78, blue: 0.08)),
    IIGSControlPanelColor(id: 0xD, name: "Yellow", color: Color(red: 0.95, green: 0.85, blue: 0.12)),
    IIGSControlPanelColor(id: 0xE, name: "Aqua", color: Color(red: 0.45, green: 0.92, blue: 0.92)),
    IIGSControlPanelColor(id: 0xF, name: "White", color: Color(red: 0.96, green: 0.96, blue: 0.96))
]

private enum DiskTestMountOption: CaseIterable, Identifiable, Equatable {
    case smartPort1
    case smartPort2
    case floppy525Drive1
    case floppy525Drive2
    case floppy35Drive1
    case floppy35Drive2

    var id: String {
        target.displayName
    }

    var target: IIGSDiskMountTarget {
        switch self {
        case .smartPort1:
            return .smartPort(unit: 1)
        case .smartPort2:
            return .smartPort(unit: 2)
        case .floppy525Drive1:
            return .floppy5_25(drive: 1)
        case .floppy525Drive2:
            return .floppy5_25(drive: 2)
        case .floppy35Drive1:
            return .floppy3_5(drive: 1)
        case .floppy35Drive2:
            return .floppy3_5(drive: 2)
        }
    }

    var title: String {
        switch self {
        case .smartPort1:
            return "SmartPort Unit 1"
        case .smartPort2:
            return "SmartPort Unit 2"
        case .floppy525Drive1:
            return "5.25 Drive 1"
        case .floppy525Drive2:
            return "5.25 Drive 2"
        case .floppy35Drive1:
            return "3.5 Drive 1"
        case .floppy35Drive2:
            return "3.5 Drive 2"
        }
    }

    var systemImage: String {
        switch self {
        case .smartPort1, .smartPort2:
            return "internaldrive"
        case .floppy525Drive1, .floppy525Drive2:
            return "externaldrive"
        case .floppy35Drive1, .floppy35Drive2:
            return "opticaldiscdrive"
        }
    }
}
