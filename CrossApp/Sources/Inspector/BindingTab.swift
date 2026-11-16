import Foundation
import MirageKit
import SwiftCrossUI

/// AuthKey and the rest of the band's binding state, plus its factory
/// identity, edited as a draft and written into the factory partition.
struct BindingTab: View {
    var model: AppModel
    let device: VirtualDevice
    @State var draft: VirtualDevice?
    @State var revealKeys = false
    @State var newKey = ""
    @State var newValue = ""

    var body: some View {
        let d = draft ?? device
        let changed = draft != nil && draft != device
        let active = model.state(of: device.id).isActive
        let pending = ImageBuilder.factoryProperties(identity: device.identity, binding: device.binding) != device.storage.factoryProperties
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection {
                Toggle("已绑定手机", isOn: bind(\.binding.bound))
                Footnote(d.binding.bound ? "Boots past setup; a companion app connects with the AuthKey."
                                         : "Boots into the setup wizard, unbound.")
            }
            if d.binding.bound {
                InspectorSection("AuthKey") {
                    TextField("认证密钥", text: bind(\.binding.authKey))
                    if !BindInfo.isValidKey(d.binding.authKey) {
                        Text("32 hex digits").font(.caption).foregroundColor(.orange)
                    }
                    Button("生成新密钥") { update { $0.binding.authKey = BindInfo.randomKey() } }
                    Footnote("The band’s persist.miwear_token_key. Companion apps authenticate with it; a new key means pairing again.")
                }
                InspectorSection("Bind Keys") {
                    row("User ID", bind(\.binding.userID))
                    if revealKeys {
                        row("Beacon Key", bind(\.binding.beaconKey))
                        row("IR Key", bind(\.binding.irKey))
                    } else {
                        InfoRow(label: "Beacon Key", value: "••••••••")
                        InfoRow(label: "IR Key", value: "••••••••")
                    }
                    row("Sequence", bind(\.binding.seqnum))
                    HStack {
                        Toggle("显示密钥", isOn: $revealKeys)
                        Spacer()
                        Button("重新生成") {
                            update {
                                $0.binding.beaconKey = BindInfo.randomKey()
                                $0.binding.irKey = BindInfo.randomKey()
                            }
                        }
                    }
                }
            }
            InspectorSection("Factory Identity") {
                row("Device ID", bind(\.identity.did))
                row("Serial", bind(\.identity.serial))
                row("Bluetooth", bind(\.identity.bluetoothAddress))
                Button("生成新身份") {
                    if let p = model.profile(device.profileID) {
                        update {
                            let extra = $0.identity.extra
                            $0.identity = FactoryIdentity.generate(for: p)
                            $0.identity.extra = extra
                        }
                    }
                }
            }
            InspectorSection("Extra Factory Properties") {
                ForEach(d.identity.extra) { p in
                    HStack {
                        Text(p.key)
                        Spacer()
                        Text(p.value).foregroundColor(.gray).lineLimit(1)
                        Button("移除") { update { $0.identity.extra.removeAll { $0.key == p.key } } }
                    }
                }
                HStack {
                    TextField("键", text: $newKey)
                    TextField("值", text: $newValue)
                    Button("添加") {
                        let k = newKey.trimmingCharacters(in: .whitespaces)
                        guard !k.isEmpty else { return }
                        let v = newValue
                        update {
                            $0.identity.extra.removeAll { $0.key == k }
                            $0.identity.extra.append(.init(key: k, value: v))
                        }
                        newKey = ""
                        newValue = ""
                    }
                }
            }
            if let error = validation(d) {
                Text(error).font(.caption).foregroundColor(.orange).padding(.top, 10)
            }
            HStack {
                if changed { Button("还原") { draft = nil } }
                Spacer()
                Button(active ? "Save for Next Boot" : "Save") {
                    guard let draft else { return }
                    model.update(draft, rewriteFactory: true)
                    self.draft = nil
                }
                .disabled(!changed || validation(d) != nil)
            }
            .padding(.top, 14)
            if pending && !changed {
                HStack {
                    Footnote(active ? "Changes are written into the factory partition after the device shuts down."
                                    : "The factory partition is out of date.")
                    Spacer()
                    if !active { Button("立即写入") { model.applyPendingFactory(device.id) } }
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: device.id) { draft = nil }
        .onChange(of: model.state(of: device.id)) {
            if model.state(of: device.id) == .stopped { model.applyPendingFactory(device.id) }
        }
    }

    private func row(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text).frame(width: 190)
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<VirtualDevice, T>) -> Binding<T> {
        Binding(get: { (draft ?? device)[keyPath: kp] }, set: { v in update { $0[keyPath: kp] = v } })
    }

    private func update(_ f: (inout VirtualDevice) -> Void) {
        var d = draft ?? device
        f(&d)
        draft = d
    }

    private func validation(_ d: VirtualDevice) -> String? {
        do {
            try d.identity.validate()
            try d.binding.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
