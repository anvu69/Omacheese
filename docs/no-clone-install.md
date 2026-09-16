# Cài không cần clone repo

Chạy setup thẳng từ GitHub, không cần `git clone`.

> Với script tải từ Internet, nên tải về đọc trước rồi mới chạy. One-liner `irm ... | iex`
> tiện nhưng chỉ nên dùng với repo bạn kiểm soát. Xem [mục safer mode](#3-safer-mode).

## 1. Windows one-liner

```powershell
irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1 | iex
```

Không cần `git`, không cần set biến gì trước. Nó tải **cả repo dưới dạng zip**
(một request, ~1.6s) rồi chạy đúng `scripts/setup.ps1` mà bản clone dùng — nên
trải nghiệm giống hệt nhau.

### Repo nằm ở đâu sau khi cài

```
%LOCALAPPDATA%\Omacheese\repo
```

**Không phải `%TEMP%`, và đây không phải chi tiết vặt.** `link-configs.ps1`
*symlink* PowerShell profile, `~/.config`, `whkdrc`, `komorebi.json` và
`%APPDATA%\alacritty` vào đúng thư mục mà installer giải nén ra. Nghĩa là thư
mục đó **chính là bản repo đã cài**, không phải chỗ tạm, và nó phải sống lâu
hơn lần chạy. Trong `%TEMP%` thì không:

- installer xoá thư mục làm việc của chính nó ở **đầu** mỗi lần chạy, nên lần
  cài thứ hai làm hỏng mọi config lần đầu đã link;
- Storage Sense và Disk Cleanup dọn `%TEMP%` theo lịch riêng của Windows.

Kết quả đều giống nhau: mọi symlink trỏ vào hư không, và triệu chứng đúng y như
một bản cài hỏng — prompt quay về PowerShell trần, Alacritty mất theme,
`SUPER + SPACE` im lặng.

Chạy `install.ps1` từ thư mục đã có `scripts/setup.ps1` bên cạnh (bản clone,
hoặc bản đã giải nén) thì nó dùng luôn bản đó, không tải đè lên.

Cài xong, bản `%TEMP%\omacheese-install` cũ (nếu có từ lần cài trước) được
`link-configs.ps1` xoá — sau khi đã trỏ lại mọi config sang chỗ mới.

Trước đây script này liệt kê từng file cần tải. Danh sách đó lạc hậu ngay khi có
file mới: đến lúc thay thì nó đã **thiếu 25 file**, trong đó có
`omacheese-menu.cmd` (thứ mà `SUPER+SPACE` thực sự chạy), scroll daemon, toàn bộ
theme system và mọi lệnh Raycast. Cài xong trông như đã cài, mà không phải.
Giờ không còn danh sách nào để lạc hậu.

Nếu zip không tải được, nó tự chuyển sang `git clone --depth 1`.

## 2. Chọn cài gì

`iex` không nhận tham số, nên bọc trong script block:

```powershell
# xem nó định làm gì, không đổi gì cả
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1))) -DryRun

# chỉ cài app, không đụng config
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1))) -Modules core,psmodules,cli,wm,desktop -Yes

# chỉ cài config, không cài app
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1))) -Modules configs -Yes
```

Hoặc tải về file rồi chạy — thói quen tốt hơn với script chạy code từ Internet:

```powershell
irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1 -OutFile install.ps1
./install.ps1 -DryRun
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

Cài từ fork hoặc nhánh khác: `-Repo owner/name` và `-Branch <tên-nhánh>`.

## 3. Safer mode

Tải về đọc trước rồi mới chạy — nên làm với bất kỳ script nào chạy code từ
Internet:

```powershell
irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1 -OutFile "$env:TEMP\install.ps1"
notepad "$env:TEMP\install.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\install.ps1" -DryRun
```

### Lệnh cũ vẫn chạy

One-liner cũ (`$repo=...; irm "$repo/scripts/bootstrap-windows.ps1" | iex`) vẫn
hoạt động — `scripts/bootstrap-windows.ps1` giờ chỉ forward sang `install.ps1`
và in ra lệnh mới.

## 4. AlmaLinux (WSL) one-liner

Phía Linux vẫn tải từng file, và ở đó `--skip-*` **có thật**:

```bash
repo="https://raw.githubusercontent.com/anvu69/Omacheese/main"
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo"

# chỉ package
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-configs

# chỉ config
curl -fsSL "$repo/scripts/bootstrap-almalinux.sh" | bash -s -- --repo "$repo" --skip-install
```

## 5. Chạy một script lẻ

```powershell
$repo="https://raw.githubusercontent.com/anvu69/Omacheese/main"
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
