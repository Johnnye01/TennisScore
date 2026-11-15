import SwiftUI
import UniformTypeIdentifiers

struct CourtBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct PhoneSettingsView: View {
    @ObservedObject var store: MatchStore
    @State private var exporting = false
    @State private var importing = false
    @State private var backup = CourtBackupFile()
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("按你的节奏。")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text("手动记分始终可用。把语音和提醒，调到刚刚好。")
                        .font(.subheadline).foregroundStyle(CourtPalette.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                Toggle(isOn: $store.preferences.speechEnabled) {
                    Label("英文比分播报", systemImage: "speaker.wave.2")
                }
                Toggle("播报包含姓名", isOn: $store.preferences.includeNamesInSpeech)
                    .disabled(!store.preferences.speechEnabled)
                Button {
                    store.speakPreview("Alex serving. Thirty-fifteen. Advantage Alex. Game, Alex.")
                } label: {
                    Label("试听专业英文播报", systemImage: "play.circle")
                }
            } header: {
                Text("听见比分")
            } footer: {
                Text("普通局先报发球方比分；抢七先报领先比分。名字可在新比赛设置中填写英文播报名并试听。")
            }
            .listRowBackground(CourtPalette.surface)

            Section {
                Toggle(isOn: $store.preferences.voiceCommandsEnabled) {
                    Label("允许 Siri 语音记分", systemImage: "waveform")
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("抬腕，提出请求。")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("开启后，可通过 Siri 运行 CourtCall 的我方得分、对方得分、撤销和报分指令。具体入口可在系统“快捷指令”中查看。")
                        .font(.footnote).foregroundStyle(CourtPalette.secondary)
                    Text("手表：设置 → Siri → 抬腕对话。也可说“嘿 Siri”唤起。实际可用性取决于设备、语言、连接及系统设置。")
                        .font(.footnote).foregroundStyle(CourtPalette.secondary)
                }
                .padding(.vertical, 5)
            } header: {
                Text("可选语音操作")
            } footer: {
                Text("关闭语音记分后，屏幕加分和撤销按钮照常可用。手机和手表的语音开关分别设置；在手表使用 Siri 前，请在手表开启语音记分。")
            }
            .listRowBackground(CourtPalette.surface)

            Section {
                Toggle(isOn: $store.preferences.changeoverRemindersEnabled) {
                    Label("换边提醒", systemImage: "arrow.left.arrow.right")
                }
                Toggle(isOn: $store.preferences.serveRemindersEnabled) {
                    Label("发球轮换提醒", systemImage: "tennis.racket")
                }
                Toggle(isOn: $store.preferences.hydrationRemindersEnabled) {
                    Label("休息与补水提醒", systemImage: "drop")
                }
            } header: {
                Text("场上提醒")
            } footer: {
                Text("补水提示跟随允许休息的换边和盘间。每盘第一局后的换边及抢七中的换边不提供休息倒计时。倒计时从你记录结束这一分时开始，仅作辅助。")
            }
            .listRowBackground(CourtPalette.surface)

            Section {
                Label(store.connectionStatus, systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.subheadline)
                Text("手表可独立手动记分。手机和手表恢复连接后会同步比赛；同一场建议由一台设备负责记分。")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
                Text("抬腕回到比赛：在手表“设置 → 通用 → 返回表盘”中，为 CourtCall 选择较长的返回时间。")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
            } header: {
                Text("Apple Watch")
            }
            .listRowBackground(CourtPalette.surface)

            Section {
                Button {
                    do {
                        backup = CourtBackupFile(data: try store.exportData())
                        exporting = true
                    } catch {
                        store.lastError = error.localizedDescription
                    }
                } label: {
                    Label("导出比赛备份", systemImage: "square.and.arrow.up")
                }
                Button { importing = true } label: {
                    Label("导入比赛备份", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("保存你的比赛")
            } footer: {
                Text("比赛保存在本机。重要记录可导出为备份文件，妥善保留。")
            }
            .listRowBackground(CourtPalette.surface)

            Section {
                HStack {
                    Text("COURTCALL").font(.system(.subheadline, design: .rounded, weight: .semibold)).tracking(2)
                    Spacer()
                    Text("1.0").font(.caption).foregroundStyle(CourtPalette.secondary)
                }
                Text("职业计分规则，适合你的赛制。")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
                Link("查看 ITF 网球规则", destination: URL(string: "https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf")!)
                    .font(.footnote)
            }
            .listRowBackground(CourtPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .courtScreen()
        .navigationTitle("设置")
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "CourtCall-backup") { result in
            switch result {
            case .success: backupMessage = "比赛备份已导出。"
            case .failure(let error): store.lastError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Data(contentsOf: url))
                backupMessage = "比赛备份已导入。"
            } catch {
                store.lastError = error.localizedDescription
            }
        }
        .alert("备份", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("好") { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
    }
}
