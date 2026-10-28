# HLCamSwap — 货拉拉注册拍照替换插件

**目标机型**：iPhone 14 Pro Max（A16）/ iOS 16.2
**越狱环境**：Dopamine 2.x（rootless）
**功能**：货拉拉注册时，拍照/选图自动替换成你指定的证件照片，支持旋转

---

## 一、前提：越狱

iPhone 14 Pro Max（A16）+ iOS 16.2 **不能用 palera1n**（那只能 A11 及以下），必须用 **Dopamine 2**：

| 项目 | 要求 |
|---|---|
| 越狱工具 | **Dopamine 2.0+**（支持 iOS 15.0–16.6.1，A12–A16） |
| 环境类型 | **rootless**（无根，tweak 装在 `/var/jb/`） |
| 包管理器 | Sileo 或 Zebra（Dopamine 自带） |

**检查是否已越狱**：主屏幕有 **Dopamine** 图标，且 Sileo 能正常安装插件。

⚠️ **注意**：Dopamine 2 对 16.2 的支持需要确认版本号，装之前先去 [dopamine.app](https://ellekit.space/dopamine/) 查一下你机型的兼容列表。

---

## 二、编译（Windows 上也能做，用 GitHub Actions）

Windows 没有 iOS SDK，**不要尝试本地编译**。用 GitHub 免费跑 macOS 编译：

### 步骤

1. 注册 GitHub 账号（没有的话）
2. 新建一个**私有仓库**（Private），名字随便，比如 `hlcam`
3. 把这个 `ios-tweak` 文件夹里的**所有内容**上传到仓库根目录，结构应该是：

```
hlcam/
├── .github/
│   └── workflows/
│       └── build.yml
├── HLCamSwap/
│   ├── Makefile
│   ├── Tweak.x
│   └── control
└── config.sh
```

4. 上传后，GitHub 会自动开始编译（Actions 标签页能看到进度）
5. 等 5–10 分钟，编译完成后：
   - 进入 **Actions** → 点最新的一次运行
   - 页面底部 **Artifacts** 里下载 `HLCamSwap-deb`
   - 解压得到一个 `.deb` 文件

> 如果没自动触发：Actions 页面 → 选 `Build HLCamSwap` → 右侧 `Run workflow` 手动跑一次。

---

## 三、安装到 iPhone

### 方式 A：Filza（推荐，最简单）

1. iPhone 上打开 **Filza**（越狱后从 Sileo 装）
2. 把 `.deb` 传到手机（隔空投送 / 微信文件传输 / iCloud 都行）
3. Filza 里找到这个 `.deb`，点开 → 右上角 **安装**
4. 装完 **respring**（Filza 里有重启 SpringBoard 的选项）

### 方式 B：Sileo 本地安装

1. 把 `.deb` 放到 `/var/mobile/Documents/`
2. Sileo → 来源 → 左上角 **+** → 选 **Local .deb** → 找到文件安装

### 方式 C：命令行（SSH）

```bash
scp HLCamSwap_1.0.0_iphoneos-arm64.deb root@<iPhone-IP>:/var/mobile/Documents/
ssh root@<iPhone-IP>
dpkg -i /var/mobile/Documents/HLCamSwap_1.0.0_iphoneos-arm64.deb
killall -9 SpringBoard
```

---

## 四、配置（关键）

插件读的是 `/var/mobile/Library/HLCamSwap/` 这个目录。

### 1. 放证件图

用 Filza 进到 `/var/mobile/Library/HLCamSwap/`（没有就新建），把证件照片拷进去：

```
/var/mobile/Library/HLCamSwap/
├── enable.txt          ← 内容写 1（启用）
├── active.txt          ← 内容写当前要用的图片文件名
├── rotate.txt          ← 内容写旋转角度
├── driving.jpg         ← 行驶证
├── driver.jpg          ← 驾驶证
└── idcard.jpg          ← 身份证
```

### 2. 用脚本配置（更省事）

把 `config.sh` 拷到手机（比如 `/var/mobile/Documents/`），然后在 **NewTerm**（越狱终端）里：

```bash
cd /var/mobile/Documents
sh config.sh enable                    # 启用插件
sh config.sh list                      # 看有哪些图
sh config.sh use driving.jpg           # 指定用行驶证那张
sh config.sh rotate 90                 # 旋转 90 度
sh config.sh status                    # 确认配置

sh config.sh log                       # 看日志（调试用）
```

### 3. 旋转角度怎么定

如果替换后图片是歪的，就调 `rotate.txt`：

| 现象 | 设置 |
|---|---|
| 正常 | `0` |
| 逆时针歪 90° | `90` |
| 倒过来 | `180` |
| 顺时针歪 90° | `270` |

改完**重启货拉拉 App** 生效（不用 respring）。

---

## 五、使用流程

```
① 确认配置：sh config.sh status       ← enable=1, 图片指定好
② 打开货拉拉 App → 走注册流程
③ 到需要拍照的步骤 → 正常点「拍照」
④ 拍一张随便什么（甚至对着桌面拍）    ← 关键
⑤ 插件在回调里把照片换成你的证件图
⑥ 页面上显示的就是你的证件照 → 点确认
```

**第 ④ 步很重要**：必须让相机真的拍一次，插件才能拦到回调。

---

## 六、插件做了什么（技术说明）

| Hook 点 | 作用 |
|---|---|
| `UIImagePickerController` delegate 的 `didFinishPickingMediaWithInfo:` | 系统相机/相册返回照片时，替换 `UIImagePickerControllerOriginalImage` |
| `AVCapturePhotoOutput.capturePhotoWithSettings:delegate:` | 自定义相机（AVFoundation）拍照时记录调用 |
| `WKWebView.setUIDelegate:` | H5 里的 `<input type="file" capture>` 通道 |

**替换流程**：

```
拍照 → 得到 UIImage → 读 /var/mobile/Library/HLCamSwap/ 里的图
     → 按 rotate.txt 旋转 → 缩放适配原图尺寸 → 塞回回调
```

**只对货拉拉生效**：`%ctor` 里判断 bundle id 是 `com.lalamove.huolala.driver` 才启动，不影响其它 App。

---

## 七、故障排查

### 插件没反应

1. **先看日志**：`sh config.sh log`
   - 如果日志是空的 → 插件没加载
   - 检查：`dpkg -l | grep hlcamswap` 确认装上了
2. **确认越狱环境是 rootless**：`ls /var/jb/` 有东西就是 rootless
3. **确认 App 真的重启过**：从后台划掉货拉拉，重新打开

### 日志显示 `没有可用图片`

- 图片没放进 `/var/mobile/Library/HLCamSwap/`
- 或者 `active.txt` 里写的文件名对不上

### 日志显示 `替换成功` 但页面还是原图

说明货拉拉读的是**另一个字段**（比如 `UIImagePickerControllerEditedImage`）。插件已经同时替换了这个字段，如果还是不行，把日志发我，我加新的 hook 点。

### 照片还是歪的

调 `rotate.txt`，4 个值轮着试一遍。

### 货拉拉检测到越狱

货拉拉可能会检测越狱环境。如果 App 直接闪退或拒绝运行：
- 装 **Choicy**（Sileo 里有），在 Choicy 里给货拉拉**关闭 tweak 注入**以外的检测
- 或者装 **Shadow** / **FlyJB X** 之类的越狱隐藏插件
- 注意：**隐藏插件和本插件可能冲突**，需要把 HLCamSwap 加进白名单

---

## 八、后续可扩展

如果当前 hook 点不够用，可以加：

1. **`PHPickerViewController` 的 delegate** —— iOS 14+ 的相册选择器
2. **`PHImageManager.requestImageForAsset:`** —— 相册读图
3. **货拉拉自有相机类的 `takePhoto` 方法** —— 需要先 dump 出类名（`class-dump` 或 `frida-ios-dump`）

需要的话把日志给我，我按实际情况补 hook。
