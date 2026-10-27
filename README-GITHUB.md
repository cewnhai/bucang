# 布仓 Bucang — GitHub 自动打包版

这个包已经是一个完整的 Xcode 工程，外加一个 GitHub Actions 自动打包流程。
你不需要在自己的电脑上装 Xcode，云上的 Mac 会帮你编出 IPA。

## 你要做的 6 步（只需要浏览器和手机）

### 1. 注册 / 登录 GitHub
打开 github.com，有账号就登录，没有就注册一个免费账号。

### 2. 新建一个空仓库
- 点右上角 + -> New repository
- Repository name 随便填，例如 `bucang`
- 选 Public（公开最省事，Actions 默认就能跑；选 Private 也可以）
- **不要勾选 Add a README、.gitignore、license**，建一个完全空的仓库
- 点 Create repository

### 3. 把这个包传上去
把本压缩包解压，得到一个文件夹，里面有 `Bucang.xcodeproj`、`Bucang`、`.github` 等。
在刚建好的空仓库页面点 Add file -> Upload files，
把解压后文件夹里的**全部内容**拖进去上传（包括隐藏的 `.github` 文件夹，浏览器拖文件夹时会一并带上；如果拖不进去，就在仓库里先建 `.github/workflows` 目录，再把 workflow 文件传上去）。
传完点最下面的 Commit changes。

检查一下：仓库根目录应该能看到 `Bucang.xcodeproj`，并且 `.github/workflows/build-ipa.yml` 在文件列表里（点进 `.github` 能看到）。

### 4. 触发打包
- 点仓库顶部的 Actions 标签
- 如果提示 workflows 被禁用，点 I understand my workflows, go ahead and enable them
- 左边点 Build Bucang IPA
- 点右边的 Run workflow -> Run workflow
- 等待运行完成，一般 5-15 分钟。绿色对勾就是成功，红色叉就是失败。

### 5. 下载 IPA
- 运行成功后，点进那次运行，拉到最下面 Artifacts，点 `Bucang-ipa` 下载
- 下载下来是一个 zip，解压后里面就是 `Bucang.ipa`
- 注意：Artifacts 只保留 90 天，下载后尽快装到手机上

### 6. 用 TrollStore 装到手机上
- 把 `Bucang.ipa` 用隔空投送 / 文件 / 数据线传到 iPhone
- 在手机上用 TrollStore 打开这个 IPA 安装
- 打开布仓，去设置 -> 导入原数据，一次选中你导出的 fabrics、tags、materials、channels、usage_records 这几个 CSV
- 核对：应为 16 条布料、3 标签、5 材质、3 渠道、0 使用记录，总长 56.14 米

## 如果打包失败怎么办

不要自己改工程，先把 Actions 那次运行的完整日志截图 / 复制报错发给我，
我按报错修工程或 workflow，再给你一个新包。最常见的失败原因：
- Xcode 版本问题：workflow 里用的是 runner 默认的最新 Xcode，一般不用改
- 某个 Swift 文件语法报错：把日志里带 `error:` 的那几行发给我
- 仓库里文件传漏了：先检查 `Bucang.xcodeproj/project.pbxproj` 和 6 个 Swift 文件都在不在

## 这个工程里有什么

- `Bucang/`：全部 Swift 源码（布料、作品、纸样、物品、字典、CSV 导入导出、设置）
- `Bucang/Assets.xcassets/`：图标和主题色（图标目前是纯色占位，以后可以换）
- `Bucang.xcodeproj/`：手写工程文件 + 共享 Scheme，GitHub Actions 就是用它编译的
- `.github/workflows/build-ipa.yml`：自动打包流程，不签名（CODE_SIGNING_ALLOWED=NO），编完再做临时签名，打包成 TrollStore 可装的 IPA
- `project.yml`：备用配置，万一手写工程打不开，在 Mac 上用 XcodeGen 按它重新生成工程即可

## 重要说明

- 这是原创重做版，名字叫布仓，Bundle ID 是 `com.example.bucang`，不是原 App 的名字和 ID
- 第一版不存图片、不做 iCloud 同步、不做订阅、不联网，数据只存在本机，就是为了避开原 App 闪退卡死的那些环节
- 这个 IPA 是你自己仓库编出来的，没有经过 App Store，不会自己更新；以后我给你新版时，重复第 4-6 步重新打包安装即可
