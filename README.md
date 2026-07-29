# VCam watermark patch

[Русский](#русский) · [English](#english) · [中文](#中文)

Скрипт убирает водяной знак `vcam.ai` в [VCam](https://www.vcam.ai/) на macOS и Windows.

Это экспериментальный патч чужого приложения. Может нарушать ToS. На свой риск.

<a id="русский"></a>
## Русский

### Запуск

```bash
# macOS
sudo bash macos/apply.sh
```

```powershell
# Windows — обязательно PowerShell от администратора
# (ПКМ по PowerShell -> Запуск от имени администратора)
powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1
```

Без админа запись в `C:\Program Files\VCam` падает с Access Denied. Потом перезапусти VCam. После обновления VCam — снова тот же скрипт.

Флаги Windows: `-AppDir "C:\Program Files\VCam"`, `-Force` (закрыть VCam без вопроса), `-Restore` (откат).

### Что делает

В `resources/frontend/App-*.js` есть метод `changeWatermarkPath`. Он кладёт PNG водяного знака в кадр. Скрипт находит этот метод и заменяет тело на:

```js
changeWatermarkPath(e){this.watermarkBuffer=void 0,this.watermarkMimeType=void 0}
```

Драйвер виртуальной камеры не трогаем. Имена минифицированных переменных не важны — ищем по скобкам.

На macOS после правки нужна ad-hoc переподпись (`entitlements` сохраняем). На Windows переподпись не нужна: подпись висит на `exe`, не на JS.

macOS при первом запуске может попросить доступ **Управление приложениями** для Terminal. После ad-hoc подписи VCam иногда заново спрашивает камеру/микрофон.

### Откат

- Windows: `.\windows\apply.ps1 -Restore`
- macOS: вернуть файл из `originals/` и переподписать:
  `codesign --force --sign - --entitlements macos/entitlements-sign.plist /Applications/VCam/VCam.app`
- или просто переустановить VCam

Если скрипт пишет, что не нашёл бандл — возможно, код уехал в `app.asar`:

```bash
npx @electron/asar extract "<VCam>/resources/app.asar" /tmp/vcam-asar
```

Ищи `changeWatermarkPath`, логика та же.

### Файлы

```
macos/apply.sh
macos/entitlements-sign.plist
windows/apply.ps1
originals/          # бэкапы, в git не лежат
```

---

<a id="english"></a>
## English

Drops the `vcam.ai` watermark from VCam's renderer. Works on macOS and Windows.

Experimental third-party patch. May break ToS. Use at your own risk.

### Run

```bash
# macOS
sudo bash macos/apply.sh
```

```powershell
# Windows — elevated PowerShell required (right-click -> Run as administrator)
powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1
```

Without admin, writing under `C:\Program Files\VCam` fails with Access Denied. Restart VCam after. Same command again after a VCam update.

Windows flags: `-AppDir`, `-Force`, `-Restore`.

### What it does

`changeWatermarkPath` in `resources/frontend/App-*.js` injects the watermark PNG into the frame. We rewrite that method to always clear the buffer:

```js
changeWatermarkPath(e){this.watermarkBuffer=void 0,this.watermarkMimeType=void 0}
```

Virtual camera driver is left alone. Brace matching, so minified names don't matter.

macOS: re-signs the app ad-hoc (entitlements kept). Windows: no re-sign needed.

First macOS run may ask for Terminal **App Management**. Ad-hoc signing can reset camera/mic prompts.

### Rollback

- Windows: `.\windows\apply.ps1 -Restore`
- macOS: restore from `originals/`, then `codesign --force --sign - --entitlements macos/entitlements-sign.plist /Applications/VCam/VCam.app`
- or reinstall VCam

If the bundle isn't found, try unpacking `app.asar` and looking for `changeWatermarkPath`.

---

<a id="中文"></a>
## 中文

去掉 VCam 渲染输出里的 `vcam.ai` 水印。支持 macOS / Windows。

实验性第三方补丁，可能违反服务条款，风险自负。

### 运行

```bash
# macOS
sudo bash macos/apply.sh
```

```powershell
# Windows（管理员 PowerShell）
powershell -ExecutionPolicy Bypass -File .\windows\apply.ps1
```

改完重启 VCam。升级 VCam 后再跑一次即可。

Windows 参数：`-AppDir`、`-Force`、`-Restore`。

### 原理

`resources/frontend/App-*.js` 里的 `changeWatermarkPath` 会把水印 PNG 塞进帧。补丁把它改成始终清空缓冲：

```js
changeWatermarkPath(e){this.watermarkBuffer=void 0,this.watermarkMimeType=void 0}
```

不碰虚拟摄像头驱动。用花括号配对定位函数体，不依赖压缩变量名。

macOS 需要 ad-hoc 重签（保留 entitlements）。Windows 不用重签。

### 还原

- Windows：`.\windows\apply.ps1 -Restore`
- macOS：从 `originals/` 还原后 `codesign --force --sign - --entitlements macos/entitlements-sign.plist /Applications/VCam/VCam.app`
- 或重装 VCam

找不到包时，解包 `app.asar`，搜 `changeWatermarkPath`。
