# Cài không cần clone repo

Chạy setup thẳng từ GitHub, không cần `git clone`.

> Với script tải từ Internet, nên tải về đọc trước rồi mới chạy. One-liner `irm ... | iex`
> tiện nhưng chỉ nên dùng với repo bạn kiểm soát. Xem [mục safer mode](#3-safer-mode).

## 1. Windows one-liner

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" | iex
```

Nó tải **cả repo dưới dạng zip** (một request, ~1.6s) rồi chạy đúng
`scripts/setup.ps1` mà bản clone dùng — nên trải nghiệm giống hệt nhau.

Trước đây script này liệt kê từng file cần tải. Danh sách đó lạc hậu ngay khi có
file mới: đến lúc thay thì nó đã **thiếu 25 file**, trong đó có
`omarchy-menu.cmd` (thứ mà `SUPER+SPACE` thực sự chạy), scroll daemon, toàn bộ
theme system và mọi lệnh Raycast. Cài xong trông như đã cài, mà không phải.
Giờ không còn danh sách nào để lạc hậu.

Nếu zip không tải được, nó tự chuyển sang `git clone --depth 1`.

## 2. Chọn cài gì

Không có `-SkipInstall` / `-SkipConfigs` ở phía Windows — dùng `-Preset` hoặc
`-Modules`:

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap.ps1"

# xem nó định làm gì, không đổi gì cả
& "$env:TEMP\bootstrap.ps1" -RepoRawBase $repo -DryRun

# chỉ cài app, không đụng config
& "$env:TEMP\bootstrap.ps1" -RepoRawBase $repo -Modules core,psmodules,cli,wm,desktop -Yes

# chỉ cài config, không cài app
& "$env:TEMP\bootstrap.ps1" -RepoRawBase $repo -Modules configs -Yes
```

**Preset:**

| Preset | Gồm |
|---|---|
| `minimal` | core, psmodules, cli, configs, verify |
| `desktop` | + wm, desktop, debloat |
| `full` | + agents, wsl |
| `everything` | + localllm |
| `custom` | tự tick trong TUI |

**Module:** `core` `psmodules` `cli` `wm` `desktop` `agents` `raycast` `configs`
`debloat` `wsl` `localllm` `verify`

Không truyền gì thì TUI mở ra, dò phần cứng và chỉ hiện những module máy đó chạy
được.

## 3. Safer mode

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap.ps1"
notepad "$env:TEMP\bootstrap.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap.ps1" -RepoRawBase $repo
```

### Nếu gặp lỗi `Set -RepoRawBase...`

Do chưa set biến `$repo` trước khi `iex`. Hai cách:

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
irm "$repo/scripts/bootstrap-windows.ps1" | iex
```

```powershell
$env:DEV_REPO_RAW="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
irm "$env:DEV_REPO_RAW/scripts/bootstrap-windows.ps1" | iex
```

Nhánh khác `main` thì thêm `-Branch <tên-nhánh>`.

## 4. AlmaLinux (WSL) one-liner

Phía Linux vẫn tải từng file, và ở đó `--skip-*` **có thật**:

```bash
repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo"

# chỉ package
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-configs

# chỉ config
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-install
```

## 5. Chạy một script lẻ

```powershell
$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
irm "$repo/scripts/doctor.ps1" -OutFile "$env:TEMP\doctor.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\doctor.ps1"
```

`doctor.ps1` chạy độc lập được. `install-windows.ps1` và `link-configs.ps1` thì
**không** — chúng cần `scripts/lib/` và `configs/` bên cạnh, nên hãy dùng
bootstrap hoặc clone.

## 6. Khi nào vẫn nên clone?

- chỉnh nhiều config cùng lúc
- version-control dotfiles cá nhân
- review diff trước khi apply
- dùng nhánh riêng cho máy work/personal/server

Chỉ bootstrap máy mới thật nhanh thì không cần clone.
