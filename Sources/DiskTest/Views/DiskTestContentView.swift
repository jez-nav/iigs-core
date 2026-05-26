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
}

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
