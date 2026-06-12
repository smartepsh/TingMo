# 发布流程

TingMo 以 Developer ID 签名 + 公证的 DMG 形式发布到 GitHub Releases,不走 App Store。

## 一次性准备

1. 钥匙串中需有 `Developer ID Application` 证书(团队 `4DUZQ8DF4R`)。
   注意:项目内 Debug 用的 `DEVELOPMENT_TEAM = 63ENVTF5NW` 仅用于本地开发签名,发布签名由脚本 env 覆盖。
2. 在 <https://account.apple.com> 生成 App 专用密码(App-Specific Password)。
3. 复制 `scripts/.env.release.example` 为 `scripts/.env.release` 并填写(已 gitignore)。
4. 安装工具:`brew install create-dmg`,`gh auth login`。

## 方式一:脚本发布(推荐)

```bash
git tag v0.1.0 && git push origin v0.1.0
./scripts/release.sh v0.1.0
```

脚本会:校验 tag 与工具 → archive(版本号取自 tag,build 号取自提交计数,强制 Hardened Runtime)→ 导出 → 公证 app → 打 DMG → 公证 DMG → `gh release create` 上传。

## 方式二:手动 Xcode 发布

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
