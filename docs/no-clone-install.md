# Install without cloning the repo

Bạn có thể chạy setup từ GitHub Raw mà không cần `git clone` toàn bộ repo.

> Khuyến nghị bảo mật: với script tải từ Internet, nên tải về đọc trước rồi mới chạy. One-liner `irm ... | iex` hoặc `curl ... | bash` tiện nhưng chỉ nên dùng với repo bạn kiểm soát.

## 1. Sau khi push repo lên GitHub

Giả sử repo của bạn là:

```text
https://github.com/<YOUR_USERNAME>/windows11-dev-poweruser
```

Raw base URL sẽ là:

```text
https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main
```

## 2. Windows one-liner

Chạy toàn bộ Windows-side install + copy config:

```powershell
$repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" | iex
```

Nếu muốn chỉ cài app, không copy config:

```powershell
$repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap-windows.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap-windows.ps1" -RepoRawBase $repo -SkipConfigs
```

Nếu muốn chỉ copy config, không cài app:

```powershell
$repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap-windows.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap-windows.ps1" -RepoRawBase $repo -SkipInstall
```

## 3. Windows safer mode

```powershell
$repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap-windows.ps1"
notepad "$env:TEMP\bootstrap-windows.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap-windows.ps1" -RepoRawBase $repo
```

## 4. AlmaLinux WSL one-liner

```bash
repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo"
```

Chỉ cài package, không copy config:

```bash
repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-configs
```

Chỉ copy config, không cài package:

```bash
repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-install
```

## 5. Chạy từng file raw riêng lẻ

Windows:

```powershell
$repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
irm "$repo/scripts/install-windows.ps1" -OutFile "$env:TEMP\install-windows.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\install-windows.ps1"
```

AlmaLinux:

```bash
repo="https://raw.githubusercontent.com/<YOUR_USERNAME>/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/install-almalinux.sh" -o /tmp/install-almalinux.sh
bash /tmp/install-almalinux.sh
```

## 6. Khi nào vẫn nên clone?

Nên clone nếu bạn muốn:

- chỉnh nhiều config cùng lúc
- version-control dotfiles cá nhân
- review diff trước khi apply
- dùng nhánh riêng cho máy work/personal/server

Không cần clone nếu bạn chỉ muốn bootstrap máy mới thật nhanh.
