# YuriGame-iOS视觉小说模拟器

## 项目介绍
**YuriGame 模拟器**是一款全面优化的 iOS galgame 模拟器，玩家可以通过模拟器在上面畅玩 galgame。

App 内提供非常强大的游戏引擎，包含了以下引擎支持：
*   **ONScripter**
*   **KiriKiri**
*   **Artemis**

 **注意**：当前版本尚在测试中，急需相关测试人员以及开发者加入。

##  系统要求与构建
*   **支持架构**：该版本只针对 `arm64`
*   **系统版本**：最低支持 `iOS 14.0` 运行
*   **构建工具**：您可以使用 [Theos](https://theos.dev/docs/) 编译此项目

### Xcode 与 Theos

项目同时提供 `YuriGame.xcodeproj` 和 Theos Makefile：

* **Xcode**：在 macOS 安装 Xcode 15 或更高版本，打开 `YuriGame.xcodeproj`，选择真机或 `iphoneos`，设置自己的 Team 后构建。工程使用 arm64、iOS 14.0，并会嵌入 `Resources/Frameworks` 与 `Resources/PlugIns`。
* **Theos**：设置 `THEOS` 环境变量后运行 `make package`。例如：`THEOS=/opt/theos make package`。未设置时主工程默认使用 `/var/theos`，子项目也可通过同一个变量覆盖。
* **子项目**：`Patch/ArtemisHook`、`Patch/XP3Touch` 和 `Patch/ONSTouch` 可分别进入目录运行 `make package`；它们共用 arm64 / iOS 14.5 目标配置。

Xcode 适合直接编译和签名应用；Theos 适合编译 tweak、打包和部署到越狱或 TrollStore 测试设备。Windows 无法运行 Xcode，需在 macOS 上执行 Xcode 构建。

##  测试说明
**设备测试情况**：

| 系统版本 | 设备型号 | 安装方式 | 测试结果 |
| :--- | :--- | :--- | :--- |
| 14.3 | iPhone 8 | 巨魔 | ✅ 正常 |
| 14.5 | iPhone 12 | 巨魔 | ✅ 正常 |
| 17.4.1 | iPad mini 5 | 自签 | ✅ 正常 |
| 18.5 | iPad mini 7 | 自签 | ✅ 正常 |
|  | iPhone 15 | 自签 | ✅ 正常 |
| 26 | 全系列设备 | 自签 | ✅ 正常 |

##  致谢 / Credits
特别感谢此项目：
https://github.com/LiveContainer/LiveContainer

##  联系方式
本项目仅为代托管。如果您对该项目感兴趣，可以联系项目作者：

*   **QQ**：`3142499905`
