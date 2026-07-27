# 发布流程

TingMo 以 Developer ID 签名 + 公证的 DMG 形式发布到 GitHub Releases,不走 App Store。

应用每天最多请求一次 GitHub `releases/latest` API，并将 `v*` tag 与当前 `CFBundleShortVersionString` 做数字版本比较。发现新版本后，用户可从菜单栏或「设置 → 系统 → 软件更新」下载 DMG；下载完成后会校验 GitHub 提供的 SHA-256 digest 并自动打开安装器。发布产物因此必须保留 `.dmg` 扩展名（现有 workflow 已满足）。

## 一次性准备

1. 钥匙串中需有 `Developer ID Application` 证书(团队 `4DUZQ8DF4R`)。
   注意:项目内 Debug 用的 `DEVELOPMENT_TEAM = 63ENVTF5NW` 仅用于本地开发签名,发布签名由脚本 env 覆盖。
2. 在 <https://account.apple.com> 生成 App 专用密码(App-Specific Password)。
3. 复制 `scripts/.env.release.example` 为 `scripts/.env.release` 并填写(已 gitignore)。仅本地发布需要。
4. 安装工具:`brew install create-dmg`,`gh auth login`。仅本地发布需要。

## 方式一:推 tag 自动发布(推荐)

```bash
git tag v0.1.0 && git push origin v0.1.0
```

推送 `v*` tag 即触发 `.github/workflows/release.yml`,在 `macos-26` runner 上跑与本地脚本**完全相同**的流程(workflow 直接调用 `scripts/release.sh --no-publish`,不重复实现签名与公证逻辑),产物为 DMG + `.sha256`,自动创建 GitHub Release 并附上自动生成的发布说明。

### 所需 GitHub Secrets

在 Settings → Secrets and variables → Actions 配置:

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application 证书导出为 `.p12` 后再 base64:`base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | 任意字符串,用于 runner 上的临时钥匙串 |
| `SIGNING_IDENTITY` | 形如 `Developer ID Application: Name (4DUZQ8DF4R)` |
| `DEVELOPMENT_TEAM` | `4DUZQ8DF4R` |
| `APPLE_TEAM_ID` | `4DUZQ8DF4R` |
| `APPLE_ID` | 用于公证的 Apple ID 邮箱 |
| `APPLE_APP_PASSWORD` | App 专用密码 |

可选变量(Variables,非 Secrets):`XCODE_VERSION` 用于钉住 Xcode 版本(如 `26.1`),不设则用镜像默认版本。`macos-26` 默认 Xcode 26.x,与本地开发工具链同代,通常无需设置。

### 首次使用与重跑

首次建议用 **Actions → Release → Run workflow** 手动触发,填 tag、`publish` 留 false:跑通全流程但不创建 Release,DMG 从 artifact 下载验证。确认无误后再推正式 tag。

同一 tag 需重跑时(如公证偶发失败)也用手动触发,**无需移动 tag**;把 `publish` 设为 true 即可发布。

### 注意

- 首跑需编译 sherpa-onnx 静态库(约 10 分钟),之后由 `actions/cache` 缓存;`scripts/build-sherpa-onnx.sh` 变更会自动失效缓存。整体超时设为 90 分钟(公证排队可能较久)。
- workflow 会校验 `TingMo/SpeechEngine/Vendor/SherpaOnnx.swift` 与上游一致,不一致则失败——避免发布未经审阅的 vendored 源码。
- 构建为 arm64-only,与 `Config/Signing.xcconfig` 中的 sherpa-onnx / onnxruntime 切片一致。

## 方式二:本地脚本发布

```bash
git tag v0.1.0 && git push origin v0.1.0
./scripts/release.sh v0.1.0
```

脚本会:校验 tag 与工具 → archive(版本号取自 tag,build 号取自提交计数,强制 Hardened Runtime)→ 导出 → 公证 app → 打 DMG → **签名 DMG** → 公证 DMG → `spctl` 验证 → `gh release create` 上传。

CI 复用的正是此脚本,因此两条路径的产物一致。

## 方式三:手动 Xcode 发布

1. 把 `MARKETING_VERSION` 改为目标版本,`CURRENT_PROJECT_VERSION` 递增(Release 配置已默认开启 Hardened Runtime)。
2. Xcode → Product → Archive(scheme: TingMo)。
3. Organizer → Distribute App → **Direct Distribution**(Developer ID),选择团队 `4DUZQ8DF4R`,Xcode 会自动提交公证,等待通过后 Export。
4. 打 DMG 并装订公证票据:

   ```bash
   create-dmg --volname "TingMo" --app-drop-link 425 190 TingMo-v0.1.0.dmg TingMo.app
   xcrun notarytool submit TingMo-v0.1.0.dmg \
     --apple-id <APPLE_ID> --password <APP_PASSWORD> --team-id 4DUZQ8DF4R --wait
   xcrun stapler staple TingMo-v0.1.0.dmg
   ```

5. 上传:`gh release create v0.1.0 TingMo-v0.1.0.dmg --generate-notes`。

## 本地测试(不发布)

```bash
git tag v0.1.0-rc1          # 本地 tag 即可,无需 push
./scripts/release.sh v0.1.0-rc1 --no-publish
```

跑完整的构建 → 公证 → DMG 流程,只跳过上传 GitHub。产物在 `build/TingMo-v0.1.0-rc1.dmg`,挂载安装后按下方步骤验证。测试完删除本地 tag:`git tag -d v0.1.0-rc1`。

## 验证安装包

```bash
spctl -a -t open --context context:primary-signature -v TingMo-v0.1.0.dmg
xcrun stapler validate TingMo-v0.1.0.dmg
```

## 常见问题

- **公证被拒**:确认 Hardened Runtime 已开启(脚本会强制注入;手动 Archive 依赖 Release 配置)。用 `xcrun notarytool log <submission-id>` 查原因。
- **公证排队慢**:首次提交可能等待较久,`--wait` 会阻塞直到完成。
- **TCC 权限丢失**:发布构建与本地开发签名不同属正常现象;本地开发请继续用 `./scripts/setup-local-signing.sh` 的稳定签名。
- **CI 报 `SIGNING_IDENTITY not present`**:secret 里的身份字符串与证书实际不符。日志会列出证书中可用的身份,照抄即可(注意需完整包含团队后缀)。
- **CI 报 vendored 源码不一致**:`scripts/build-sherpa-onnx.sh` 会用上游的 `SherpaOnnx.swift` 覆盖仓库内的副本。本地重跑该脚本,提交更新后的文件再发布。
- **CI 构建产物需重新验证**:workflow 已自动跑 `spctl` 与 `stapler validate`;失败会中止且不创建 Release。
- **`spctl` 报 `source=no usable signature`**:DMG 容器本身未签名。`create-dmg` 产出的是无签名磁盘映像,必须在公证前 `codesign` 一次——注意**公证与 `stapler staple` 对未签名容器同样会成功**(它们校验的是里面已签名的 `.app`),所以只有 `spctl` 能发现此问题。脚本现已包含该签名步骤(v0.2.1 发布时因缺此步骤而失败)。
