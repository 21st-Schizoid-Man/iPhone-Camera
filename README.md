# 拾光相机 · Moment Camera

原生 iPhone 相机原型，最低 iOS 17，使用 SwiftUI、AVFoundation、Photos 和 Core Image，无第三方 iOS 依赖。

## 已编写的功能

- 拍照、有声录像、切换前后摄像头、照片闪光灯、保存到系统相册。
- 专业面板：自动或手动曝光，ISO、快门、曝光补偿、手动对焦、色温；按当前镜头能力限制参数。
- 正常、暖调负片、冷调反转片、黑白胶片四种照片风格；对成片进行处理并保留曝光元数据。
- 相机、麦克风、仅添加照片权限；录像时长显示；保存失败时保留本地副本，可重试或分享导出。
- 默认中文界面、VoiceOver 按钮标签；本应用不上传拍摄内容，不需要应用账号。系统相册和设备备份仍遵循用户自己的 iCloud 设置。

当前胶片风格仅用于照片成片，取景器和录像显示正常模式。专业参数可在开始拍摄前调整，录像中暂不支持调整。只使用前、后置主摄；尚未实现超广角/长焦选择、RAW/ProRAW、实时胶片预览、胶片录像、LUT 导入、直方图或峰值对焦。大多数 iPhone 摄像头光圈固定，不能用软件模拟真实可变光圈。风格采用独立名称，不代表索尼、尼康、佳能、哈苏或徕卡官方色彩。

## 先在你自己的 iPhone 上安装

这条路径不要求 Apple Developer Program 付费会员；免费签名有有效期和设备数量限制。需要 Mac、Xcode，以及 iOS 17 或以上的 iPhone。

1. 在 Mac 安装支持手机系统版本的 Xcode，并打开一次完成组件安装。
2. 双击本目录的 `MomentCamera.xcodeproj`，或在终端执行 `open MomentCamera.xcodeproj`。
3. 在 Xcode → Settings → Accounts 添加你的 Apple ID；无需把账号密码发给别人。
4. 选择蓝色项目图标 → TARGETS → MomentCamera → Signing & Capabilities。
5. 勾选 Automatically manage signing，Team 选择你的 Personal Team。把 Bundle Identifier 改为你独有的反向域名，例如 `com.yourname.momentcamera`。
6. 连接并信任你的 iPhone，在手机设置中按系统提示开启开发者模式。
7. 在 Xcode 顶部选择你的 iPhone，点击运行。按提示允许摄像头、保存照片权限；第一次录像时再允许麦克风。

模拟器可以用于编译和图像处理单元测试，不能验证真实摄像头、麦克风或镜头参数。

## 构建和测试

在 Mac 的项目根目录执行：

```sh
xcodebuild -version
xcodebuild -project MomentCamera.xcodeproj -scheme MomentCamera \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
```

从最后一条命令选取一个可用 iPhone 模拟器 UDID，然后执行：

```sh
xcodebuild -project MomentCamera.xcodeproj -scheme MomentCamera \
  -configuration Debug -destination 'platform=iOS Simulator,id=替换为模拟器UDID' \
  -derivedDataPath build/DerivedData -resultBundlePath build/CameraTests.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

也可以在 Xcode 中选择模拟器后按 Command-U。当前有 6 个 XCTest 用例，检查原片不变、胶片成片有效且彼此不同、竖向照片方向与曝光元数据、损坏输入处理，以及保存失败时的本地文件持久化。

`.github/workflows/ios.yml` 配置了 macOS 上的模拟器构建和这些测试。需要把代码推送到 GitHub 后才能执行；此工作流不包含签名或 TestFlight 上传。

## 当前验证状态

本次开发所在的 Linux 云环境没有 Xcode、iOS SDK、模拟器或相机。已执行 Swift 语法解析、Xcode 工程引用、共享 scheme、权限 plist 和图标检查。**尚未进行 Swift 类型检查、Xcode 构建、XCTest 执行、真机拍摄、签名或 TestFlight 上传。** 这是需要在 Mac 上继续验证的原型，不能把源码检查通过视为应用已经可用。

云端源码检查：

```sh
python3 -m venv /workspace/.camera-source-tools
/workspace/.camera-source-tools/bin/python -m pip install --no-cache-dir \
  -r scripts/source-check-requirements.txt
/workspace/.camera-source-tools/bin/python scripts/check-source.py
```

已有共享 Xcode 工程，无需 XcodeGen 或 CocoaPods。增加或删除 Swift 文件后可运行 `python3 scripts/generate_project.py` 更新工程；生成器会覆盖工程和共享 scheme，先保留你在 Xcode 做过的签名或其他自定义设置。普通源码修改无需重新生成工程。

## 上传 TestFlight 的必要条件

需要 [Apple Developer Program](https://developer.apple.com/programs/enroll/) 有效会员，以及 App Store Connect 访问权限。没有付费会员时可以做上面的个人真机测试，但不能上传 TestFlight。

会员生效、构建与真机验证通过后：

1. 在 Apple Developer 注册唯一的 Bundle ID，Xcode 的 Team 和 Bundle Identifier 与其一致。
2. 在 App Store Connect 创建 iOS App，选同一个 Bundle ID，填写应用名称、语言和 SKU。
3. 确认当前构建符合上传当时 Apple 的 Xcode / iOS SDK 要求；完善图标与隐私信息。
4. 在 Xcode 选择可归档的 iOS 设备目标，执行 Product → Archive。
5. 在 Organizer 执行 Validate App，再 Distribute App → App Store Connect → Upload。
6. 等待 Apple 处理完构建，在 TestFlight 中完成出口合规等信息，再添加测试人员。内部测试人员需要 App Store Connect 的合适角色；外部测试可能需要 Beta App Review。
7. 在 iPhone 安装 TestFlight，通过邀请安装测试版。

本仓库未放入证书、私钥或账号密码。不要在聊天或 Git 中发送 `.p8`、`.p12`、密码和验证码。后续协作上传需通过受支持的安全授权方式或在你自己的 Mac 上使用 Xcode 登录。

## 真机验收清单

- 首次授权、拒绝权限后进入设置恢复、前后台切换、相机被占用后的重试。
- 前后置拍照，闪光灯三种模式，正常及每种胶片照片，竖向成片和相册保存。
- 录像有声音、停止后可在相册播放、切入后台时结束录像并保存、录制中断和存储不足。
- ISO、快门、对焦、色温、曝光补偿确实改变拍摄效果；恢复自动；切换镜头后参数范围有效。
- 胶片处理失败会尝试保存正常原片。相册保存失败时确认左下角出现待保存入口，重启后仍可重试保存或分享导出；同时验证磁盘已满、连本地备份也失败时的提示。
- 小屏 iPhone、VoiceOver、中文文字布局，以及长时间拍摄的温升和电量。
