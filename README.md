# CourtCall · 随身网球记分员

原生 iPhone + Apple Watch 个人记分工具。手动加分始终可用，Siri 语音记分和英文播报分别开关。

项目最低支持 iOS 17 / watchOS 10。没有服务器、订阅或第三方运行时依赖；比赛先保存在各自设备，连接恢复后合并逐分记录。

当前交付是 Xcode 源码项目。Apple SDK 的 iPhone / Watch 模拟器构建已在 GitHub 的 Mac 环境通过；手表音频、Siri 和配对设备同步仍需真机验证。检查范围与步骤见 [Docs/TESTING.md](Docs/TESTING.md)。

同一组 38 项 Swift 测试已在 Linux 和 Mac 均通过，并检查了所有 Swift 文件的语法、Xcode 工程与两端资源配置。[Mac 构建与测试结果](https://github.com/Johnnye01/TennisScore/actions/runs/43754005439)

## 第一次装到自己的设备

需要一台 Mac、支持你当前 iPhone / Apple Watch 系统版本的 Xcode，以及已配对的 iPhone 和 Apple Watch。项目本身不要求付费开发者账号。

1. 解压整个项目，双击 `CourtCall.xcodeproj`。不要只复制其中一个 Swift 文件。
2. 在 Xcode → Settings → Accounts 登录自己的 Apple Account。
3. 打开项目中的 `Configuration / Personal.xcconfig`，把 `COURTCALL_BUNDLE_PREFIX` 改成自己的唯一标识，例如 `com.yourname.courtcall`。这是一次性配置，之后续签保持不变。
4. 在项目两个 Targets（`CourtCall`、`CourtCallWatch`）的 Signing & Capabilities 中，选择同一个 **Personal Team**，保留 Automatically manage signing。两个 Bundle Identifier 会从前缀生成，手表端以 `.watchkitapp` 结尾。
5. 连接 iPhone，信任这台 Mac。按 Xcode 提示在 iPhone / Apple Watch 开启开发者模式；首次配置可能需要重启设备。
6. 选择 `CourtCall` Scheme 和自己的 iPhone，点击 Run。若手表上未自动出现 App，在 iPhone 的 Watch App 中安装 CourtCall，或切换到 `CourtCallWatch` Scheme，选择配对的 Apple Watch 后 Run。
7. 在手机与手表上分别打开一次 CourtCall。手机创建比赛，确认手表收到比赛并能手动加分。比赛时可以把手机放在场边。

初次标识配置也可在终端执行：

```sh
python3 Scripts/configure_signing.py --bundle-prefix com.yourname.courtcall
```

如果知道自己的 10 位 Team ID，可以追加 `--team ABCD123456`。这会同时配置两端；不需要提供密码、证书或私钥给脚本。

## 免费账号续签

Apple 当前 Personal Team 描述文件在签发 7 天后过期。到期后 App 无法正常启动；在 Mac 上更新签名并覆盖安装，即可继续开发测试使用。Apple 未公布累计续签次数或总使用天数上限，但仍有 App ID、设备和安装数量配额。[Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)

- 保留原来的项目、Apple 账号 / Team 和 Bundle Identifier。
- 用 Xcode 更新签名并重新安装 iPhone、Watch 两端，不必修改代码。
- **不要先卸载 App**。覆盖更新通常保留本地比赛数据；另用手机“设置”中的导出功能保存备份。
- 每次点击 Run 不一定重新获得完整 7 天：Xcode 可能复用尚有效的描述文件，期限按描述文件签发时间算。重装旧包不会延长旧签名。
- 打球前确认有效期覆盖比赛，并在两端各打开一次检查。签名仍有效时，不必每次出门都重新安装。

[Apple 描述文件更新说明](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/)、[Xcode 增量更新与数据说明](https://developer.apple.com/documentation/xcode/testing-a-release-build)

## 开始一场比赛

在 iPhone 创建比赛，选择单打 / 双打，填写双方名字；英文播报名可独立填写并试听。双打还需确定队内发球先后、左右接发人，混双无占先规则需要准确的球员性别。选择先发球队与起始场地端，之后 App 自动追踪轮换。

提供 ATP 单打、ATP 双打和自定义预设。自定义赛制对应已确认的玩法：

- 一盘定胜负 / 三盘两胜 / 五盘三胜。
- 每盘目标 2 / 4 / 6 局，至少领先两局；到 2–2 / 4–4 / 6–6 时抢七。
- 三盘制 1–1 或五盘制 2–2 时，用抢十替代完整决胜盘。一盘制不会在 0–0 时直接抢十。
- 抢七和抢十都要求领先两分。

ATP 单打预设保留完整决胜盘；ATP 双打采用无占先和决胜抢十。选择自定义后会显示实际规则摘要。详见 [Docs/RULES.md](Docs/RULES.md)。

手机和手表上的两个大按钮分别给我方 / 对方加一分，位置不随换边互换。撤销会一起恢复比分、发球人、左右发球区、接发人及场地端。No-Ad 决胜分若需要接发方选择发球区，先选右区或左区再继续记分。

## 语音和提醒

语音输入和输出是独立选项，各设备分别保存自己的设置：

- **英文播报**：可以手动记分并自动听取职业风格比分，也可以关闭播报只保留屏幕 / 振动反馈。
- **Siri 语音记分**：默认关闭；开启后可通过 CourtCall 的快捷指令给我方 / 对方加分、撤销或重报。无需开启语音才能手动完成比赛。具体口令以设备“快捷指令”中 CourtCall 显示的建议为准。
- **抬腕对话**：在支持的设备 / 语言下，可在手表设置 → Siri 中开启并先用系统命令测试。该入口调用 Siri；本 App 不会持续录音监听。
- **发球提醒**：更新下一分的发球人、Deuce / Ad 发球区及接发人。
- **换边提醒**：单独提醒交换场地两端。
- **补水提醒**：在允许休息的换边和盘间提供可关闭的提示。每盘第一局后及抢七中的换边不会自动启动补水休息。

手表 TTS 的声音出口、音量以及 Siri 的触发 / 确认步骤受设备、系统和音频设置影响；首次使用请在场地试听。正常计分不需要麦克风权限。

内置快捷指令口令包括“用 CourtCall 给我方加分”“用 CourtCall 给对方加分”“用 CourtCall 撤销上一分”“用 CourtCall 报比分”。No-Ad 决胜分还可说“用 CourtCall 选择右区接发”或“用 CourtCall 选择左区接发”。抬腕对话之外，可按设备设置在口令前加 Siri 唤醒词。

## 落腕后继续记分

在 Apple Watch 的设置 → 通用 → 返回表盘，找到 CourtCall，设置为 **1 小时后**返回表盘。这样比赛中抬腕通常能直接回到比分界面。菜单名称可能因 watchOS 版本略有不同。

落腕熄屏不会清空比赛。App 会在每次操作后保存，重新打开也可继续；此版本没有用 HealthKit 运动会话来保持界面，也不承诺后台持续监听。系统切走界面时，可从表盘 / App 列表重新进入。[Apple 显示设置说明](https://support.apple.com/guide/watch/adjust-the-display-settings-apd127ec93ac/watchos)

## 备份与同步

手机“设置”可导出 JSON 备份，并从备份导入合并比赛。文件包含球员姓名、比赛配置和逐分操作，适合保存在自己的文件 App 中。

两端通过 WatchConnectivity 交换带唯一 ID 的记录，重复传输不会重复加分。离线期间先本地记分，重新连接并打开两端后合并。导入也是合并，已有记录不会因为重复导入而再次计入。

## 开发与构建

直接打开已生成的 `.xcodeproj` 即可，不需要 CocoaPods、XcodeGen 或后端服务。纯规则和事件文档可单独执行：

```sh
swift test
python3 Scripts/validate_project.py
```

新增 / 删除 Swift 文件后，用下面的标准库脚本重新生成显式源文件列表。它保留 `Config/Personal.xcconfig`；自定义 Xcode 项目设置可能被重新生成覆盖。

```sh
python3 Scripts/generate_project.py
```

目录分工：

| 目录 | 内容 |
|---|---|
| `Sources/CourtCore` | 可重放的计分引擎、职业播报及轮换规则 |
| `Sources/CourtSession` | 操作记录、撤销、合并和备份数据 |
| `Apple/Shared` | 本地存储、两端同步、TTS、Siri App Intents |
| `Apple/iPhone` | 比赛设置、手机比分界面、历史和备份 |
| `Apple/Watch` | 手表快速记分、提示和独立控制 |
| `Tests` | 规则与事件合并测试 |
| `Scripts` | 项目生成、结构校验和签名标识配置 |

仓库附带 macOS GitHub Actions 构建配置。项目已保存到指定的 TennisScore 仓库，并已通过未签名模拟器构建。检查会保存日志、结果和成功构建的模拟器 App；模拟器包不能直接安装到 iPhone 或 Apple Watch 真机，真机仍按前面的步骤选择个人 Team 签名安装。
