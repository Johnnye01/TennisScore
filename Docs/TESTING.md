# 验证范围与真机检查

当前制作环境是 Linux。纯 Swift 规则 / 事件文档测试与项目结构检查可以在这里执行；SwiftUI、WatchConnectivity、App Intents 和手表音频需要 Apple SDK 或配对真机，不能用 Linux 语法检查代替。

本次已实际完成：Swift 6.0.3 编译并通过 **38 项 XCTest**（31 项规则、7 项事件文档）；全部 Swift 文件语法解析通过；项目结构校验通过；Apple 的 `plutil` 工具检查 `.pbxproj` 与两端 `Info.plist` 通过。尚未运行 Apple SDK 的完整编译、模拟器或配对真机测试。

## 自动检查

```sh
swift test
python3 Scripts/validate_project.py
```

`validate_project.py` 检查实际 `.pbxproj` 语法和对象引用、两端源文件归属、嵌入手表应用的依赖与身份、Info.plist、共享 Scheme、图标文件尺寸及不透明 RGB 格式。

评分和文档测试应覆盖：占先 / 无占先、2 / 4 / 6 局、单盘与决胜抢十、抢七发球轮换、双打接发顺序、换边、撤销、记录合并和重复传输。

## Mac 上的 Apple SDK 构建

项目带两个共享 Scheme：`CourtCall`、`CourtCallWatch`。在安装了相应模拟器 SDK 的 Mac 上，可运行：

```sh
xcodebuild -project CourtCall.xcodeproj -scheme CourtCall \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iPhone CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CourtCall.xcodeproj -scheme CourtCallWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/Watch CODE_SIGNING_ALLOWED=NO build
```

不要给整个 iPhone + Watch 依赖图强行传 `-sdk iphonesimulator`：两个目标各自选择适合的平台 SDK。

`.github/workflows/apple-build.yml` 提供相同的 macOS CI 路径，并保存构建日志、`.xcresult` 与成功产出的模拟器 App 压缩包，默认保留 7 天。模拟器包不能直接安装到真实 iPhone / Apple Watch；真机仍须用自己的账号签名。构建是否通过以对应 GitHub Actions 运行结果为准。

## 第一次真机联调

1. 以免费 Personal Team 安装 iPhone / Watch 两端；断开 Xcode 调试器，从主屏幕启动，避免调试器影响后台行为。
2. 创建单打和双打比赛，确认名称、队伍、赛制、先发球人、左右接发人与初始场地端正确。
3. 关闭语音输入，连续手动加分并撤销；确认全场可以独立完成。
4. 在 40–40、No-Ad 决胜分、2–2 / 4–4 / 6–6、抢七每六分、抢七结束、决胜抢十等节点检查提示与比分。
5. 在新盘开始前调整双打队内顺序；开始得分后不允许随意改序。
6. 分别开关手机和手表英文播报，验证姓名发音、扬声器 / 耳机路由和音量。两端偏好独立，按自己的使用方式设置，避免不需要的重复出声。
7. 开启 Siri 语音记分，再执行我方 / 对方得分、撤销、重报；检查抬腕入口、锁屏、额外确认和响应时间。关闭语音记分后，手动计分仍工作，Siri 加分应拒绝执行。
8. 设置 CourtCall 一小时后返回表盘，反复落腕 / 抬腕，确认能回到比分；也测试系统切走 App 后重新进入恢复比赛。
9. 暂时让设备断连，在手表继续得分；重新连接并打开两端，检查记录合并且不重复加分。再测手机与手表分别产生离线记录。
10. 导出 JSON，重复导入，确认比赛和分数不重复；保留原 Bundle Identifier 覆盖安装，检查历史仍在。
11. 在真实球场打一整盘，记录误触、漏听、错误加分、耗电，以及风声 / 喘气 / 旁人喊声对 Siri 的影响。

## 本版本的实际边界

- 不持续采集麦克风，不承诺比赛全程免唤醒监听。
- 不使用 HealthKit 运动会话保活；依赖系统返回表盘设置与本地恢复。
- 本地保存和异步同步不等于远程实时直播；连接与系统调度会影响更新到达时间。
- 两端同时离线操作会按逻辑序号合并并保留原始记录。建议同一回合只由一台设备记分；如果并发操作导致接发选择等前置条件冲突，界面会提示核对比分和导出备份。
- 计时来自用户记录比赛事件的时刻，未使用传感器判断实际落球时间。
- 免费账号覆盖安装和系统能力可用性，最终以当前 Xcode / 账号 / 设备的签名结果为准。
