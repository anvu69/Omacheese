# TUI installer

```powershell
./scripts/setup.ps1
```

Một lệnh cho máy Windows vừa cài xong: dò phần cứng → chọn module → chạy và
theo dõi tiến trình.

---

## Vì sao phải zero-dependency

Đây là ràng buộc quyết định mọi thứ khác: **một máy Windows 11 vừa cài xong chỉ
có Windows PowerShell 5.1**. Không pwsh 7, không fzf, không node, không module
nào từ PSGallery. Bất cứ TUI nào cần cài thêm gì đó đều rơi vào bài toán con gà
quả trứng.

Nên `scripts/lib/tui.ps1` tự vẽ bằng ANSI thuần và:

- không dùng `?.`, `??`, ternary — đều là cú pháp PowerShell 7, và trên 5.1
  chúng là **parse error**, script chết trước khi in được dòng nào
- không dùng `` `e `` — escape này chỉ có từ PowerShell 6; trên 5.1 dấu backtick
  bị nuốt và bạn được chuỗi `"e[0m"` in ra rác
- tự bật `ENABLE_VIRTUAL_TERMINAL_PROCESSING` qua `SetConsoleMode`, vì conhost
  (khác Windows Terminal) không bật sẵn — không có bước này thì màu hiện thành
  escape code

`doctor.ps1` và CI đều parse mọi script bằng chính `powershell.exe` 5.1. Check
này đã bắt được một lỗi thật: `link-configs.ps1` dùng `?.Source`, nghĩa là trên
máy sạch nó **không chạy được**.

---

## Màn hình

**1. Chọn preset**

```text
+- Omacheese --------------------------------------------------------+
| Microsoft Windows 11 Pro  build 26200   32 GB RAM   24 threads      |
| GPU  NVIDIA GeForce RTX 4080 SUPER  16 GB VRAM  CUDA 8.9            |
| WSL  AlmaLinux-9    local LLM  16 GB VRAM - vLLM in a GPU container |
+---------------------------------------------------------------------+
| > Minimal        Terminal, shell, CLI tools, dotfiles. No tiling WM. |
|   Desktop        Minimal + tiling WM with the Omarchy keymap         |
|   Full           Desktop + coding agents + WSL2 AlmaLinux            |
|   Everything     Full + local LLM, where the hardware allows it      |
|   Custom         Pick modules yourself                               |
+---------------------------------------------------------------------+
```

**2. Chỉnh module** — `[-]` là máy không chạy được, kèm lý do:

```text
| > [x] core         PowerShell 7, Alacritty, git, Nerd Font          |
|   [x] wm           komorebi + whkd + yasb (Omarchy keymap)          |
|   [ ] debloat      Win11Debloat + the tweaks a tiling WM needs      |
|   [-] wsl          WSL2 + AlmaLinux 9                               |
|         enable virtualisation (VT-x/AMD-V) in the BIOS first        |
|   [-] localllm     Local LLM: Ollama (small models)                 |
|         needs winget to install Ollama                              |
+---------------------------------------------------------------------+
| 3 selected   space toggle  a all  n none  enter start  q quit        |
```

**3. Tiến trình** — mỗi module một dòng, cập nhật khi chạy:

```text
+- Installing  [3/7] ------------------------------------------------+
|   ok   core           74s                                           |
|   ok   cli            112s                                          |
|   >>   wm             started 01:15:42                              |
|   ..   desktop                                                      |
+---------------------------------------------------------------------+
| wm  komorebi + whkd + yasb (Omarchy keymap)                          |
| logs: C:\Users\you\AppData\Local\Temp\w11-setup-20260916-011512      |
```

Mỗi module ghi log riêng (`core.log`, `wm.log`…), nên khi hỏng có thứ để đọc
thay vì một bức tường scrollback.

Phím: `↑↓` hoặc `j/k`, `space` toggle, `a` chọn hết, `n` bỏ hết, `enter` chạy,
`q`/`Esc` thoát.

---

## Không tương tác

```powershell
./scripts/setup.ps1 -Preset desktop -Yes
./scripts/setup.ps1 -Preset everything -DryRun
./scripts/setup.ps1 -Modules core,cli,configs -Yes
```

| Preset | Module |
|---|---|
| `minimal` | core, cli, configs, verify |
| `desktop` | + wm, desktop, debloat |
| `full` | + agents, wsl, distro |
| `everything` | + localllm (nếu phần cứng cho phép) |

`-DryRun` in kế hoạch rồi dừng, không đổi gì.

---

## Gating theo phần cứng

`scripts/lib/detect.ps1` dò một lần, mọi module hỏi kết quả đó.

| Module | Yêu cầu |
|---|---|
| core, cli, wm, desktop, agents | winget |
| wsl, distro | Windows 10 2004+ và **virtualisation bật trong BIOS** |
| localllm | xem bảng tier dưới |

VRAM đọc từ `nvidia-smi`, **không** từ `Win32_VideoController.AdapterRAM` —
field đó là 32-bit và báo sai với mọi card trên 4 GB (máy test báo 4 GB cho một
card 16 GB). Detection cũng lọc bỏ virtual display adapter (Parsec, IDD…) để
không nhầm chúng là GPU thật.

### Tier local LLM

| Điều kiện | Tier | Cài gì |
|---|---|---|
| NVIDIA ≥ 8 GB VRAM | `vllm` | Docker + NVIDIA Container Toolkit + vLLM trong WSL |
| NVIDIA 4–8 GB, hoặc iGPU/AMD, hoặc RAM ≥ 16 GB | `ollama` | Ollama trên Windows, model GGUF nhỏ |
| còn lại | `none` | module bị ẩn, gợi ý dùng API hosted |

vLLM là mục tiêu ban đầu của repo nhưng **phần lớn máy không chạy nổi**, nên nó
không còn là mặc định. Ollama không cần WSL, Docker hay CUDA.

Model cũng chọn theo VRAM chứ không hard-code:

| VRAM | Gợi ý |
|---|---|
| ≥ 40 GB | Qwen3-32B fp8 |
| ≥ 22 GB | Qwen3-14B fp8 |
| ≥ 14 GB | Qwen3-8B fp8 |
| ≥ 10 GB | Qwen3-8B awq |
| ≥ 8 GB | Qwen3-4B fp8 |

Card trước Ada (compute < 8.9) không có FP8 native nên tự chuyển sang AWQ.
`install-localllm.ps1` ghi `~/.config/ai/.env` theo kết quả này, và **không bao
giờ đè** file `.env` đã có (nó giữ HF token).

---

## Backup: máy đã có config sẵn

Mọi file bị thay đều được backup **trước**, vào **một folder duy nhất cho mỗi
lần chạy**:

```text
%USERPROFILE%\.config\omacheese\backups\<timestamp>\
    C\Users\ban\.config\whkdrc
    C\Users\ban\.config\yasb\config.yaml
    C\Users\ban\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
    manifest.tsv
```

Cây thư mục mirror đường dẫn gốc nên nhìn là biết file nào ở đâu ra.
`manifest.tsv` map backup -> đường dẫn gốc.

Đường dẫn được **in ra ở màn hình cuối của TUI** và cuối output của
`link-configs.ps1`:

```text
| Your previous config was backed up (5 file(s)):                      |
|   C:\Users\ban\.config\omacheese\backups\20260916-013020|
|   restore: ./scripts/restore-backup.ps1                              |
```

Hoàn tác:

```powershell
./scripts/restore-backup.ps1 -List      # xem các lần backup
./scripts/restore-backup.ps1 -WhatIf    # xem sẽ khôi phục gì
./scripts/restore-backup.ps1            # khôi phục lần gần nhất
./scripts/restore-backup.ps1 -From <path>
```

### Git identity không bị mất

Trường hợp nguy hiểm nhất khi cài lên máy đã dùng: `~/.gitconfig` bị thay và
`user.name`/`user.email` biến mất - commit tiếp theo hỏng mà không có gì báo.

`link-configs.ps1` đọc identity cũ và ghi vào `~/.gitconfig.local`, file mà
gitconfig của repo `[include]` vào và repo **không bao giờ đụng tới**:

```text
  + kept git identity in C:\Users\ban\.gitconfig.local
    BeHax <email@example.com>
```

---

## Hai phiên bản PowerShell

Repo chạy trên cả hai, và chúng **không giống nhau** ở những chỗ quan trọng.

| | Windows PowerShell 5.1 | PowerShell 7 |
|---|---|---|
| Có sẵn trên máy sạch | có | không (winget cài qua `core`) |
| Dùng cho | `setup.ps1` và mọi script cài | profile hằng ngày, helper Omacheese |
| Module path | `Documents\WindowsPowerShell\Modules` | `Documents\PowerShell\Modules` |

### Cú pháp PS 7 gây parse error trên 5.1

`?.`  `??`  ternary `? :`  `&&`  `||`  `` `e ``

Script chết **trước khi in dòng nào**. `doctor.ps1` + CI parse mọi script bằng
chính `powershell.exe` 5.1 nên bắt được nhóm này.

### Nguy hiểm hơn: cú pháp parse được nhưng chạy sai

Parse check **không** bắt được nhóm này, chỉ chạy thật mới lộ:

| Viết | Trên 5.1 |
|---|---|
| `'a'..'z'` | throw, trả mảng rỗng — từng làm doctor báo failure giả |
| `ConvertFrom-Json -AsHashtable` | tham số không tồn tại |
| `Get-Content -AsByteStream` | dùng `-Encoding Byte` |
| `Split-Path -LeafBase` | không có |
| `ForEach-Object -Parallel` | không có |
| `Set-Content -Encoding utf8NoBOM` | không có (utf8 = **có BOM**) |

### Bẫy không liên quan phiên bản nhưng dễ dính

**`powershell.exe -File` không tách comma.** `-Modules a,b` vào `[string[]]`
thành **một** phần tử; `-Command` thì tách. Script tự split, và
`install-windows.ps1` bỏ `ValidateSet` vì nó reject trước khi split kịp.

**Gán mảng vào biến param kiểu `[string]`** khiến PowerShell ép về string,
**nối bằng dấu cách**. Từng làm 5 module thành một tên `"A B C D E"`.

### Module phải cài bằng pwsh 7

Hai PowerShell không dùng chung thư mục module. Profile là PS7-only, nên cài
module từ 5.1 sẽ rơi vào chỗ PS7 không đọc → profile hỏng âm thầm.

`Install-PowerShellModule` luôn shell ra `pwsh` và xử lý hai thứ chỉ 5.1 cần:
**TLS 1.2** (PSGallery bỏ 1.0/1.1) và **NuGet provider** (bootstrap của nó là
prompt tương tác — sẽ treo installer).

```powershell
./scripts/install-windows.ps1 -ModulesOnly
./scripts/doctor.ps1     # mục "powershell 7 modules"
```

### Helper Omacheese không phụ thuộc pwsh

whkdrc gọi `omacheese-run.cmd`, chọn pwsh nếu có, không thì `powershell.exe`.
Trước đây 11 binding hardcode `pwsh` và im lặng không làm gì khi bỏ qua `core`.

### Ngược lại: debloat **bắt buộc** 5.1

`Win11Debloat` gọi `Get-AppxPackage` và `Get-ComputerRestorePoint`. Module
`Appx` không nạp được trong pwsh 7 — nó fail với *"Operation is not supported on
this platform"* (0x80131539) — nên bản upstream **từ chối chạy** khi
`$PSVersionTable.PSEdition` là `Core`.

Đây không phải chuyện lý thuyết. `setup.ps1` chạy mọi bước bằng đúng host đã
khởi động nó, nên "cài PowerShell 7 bằng tay rồi chạy lại setup từ pwsh" — phản
xạ tự nhiên khi one-liner lỗi — chính là thứ biến bước debloat thành lỗi cứng.

`Invoke-Step -WindowsPowerShell` giải quyết: bước debloat luôn chạy bằng
`powershell.exe` 5.1, và `-Elevate` để nó không phải hỏi.

---

## Thêm module

Sửa `scripts/lib/modules.ps1`:

```powershell
$mods.Add((New-Mod -Key "mything" -Description "What it does" `
    -Available ($Machine.RamGb -ge 16) -Note "needs 16 GB RAM" `
    -Default $false -Est "2 min" `
    -Action { param($ctx) & $ctx.MyThing }))
```

rồi thêm `MyThing` vào `$ctx` trong `setup.ps1`. Mỗi action chỉ gọi một script
trong repo, nên script đó vẫn chạy độc lập được.

---

## Khi hỏng

```powershell
./scripts/setup.ps1 -Modules wm,configs    # chạy lại vài module
./scripts/doctor.ps1                       # kiểm tra đầy đủ
```

Module đều idempotent: cài rồi thì bỏ qua, config thì backup trước khi ghi đè.
Chạy lại toàn bộ là an toàn.

---

## Những lỗi máy mới từng gặp, và chỗ đã sửa

Tất cả đều chỉ xuất hiện trên **máy vừa cài Windows**, nên máy dev không thấy.

### `irm ... | iex` lỗi ngay ở dòng `iex`

Windows 11 sạch để execution policy của Windows PowerShell ở `Restricted`. Bản
thân `irm | iex` không bị chặn — đoạn text đó không chạm đĩa — nên one-liner
chạy, in banner, rồi chết ở đúng việc đầu tiên nó làm: `& <repo>\scripts\setup.ps1`.
PowerShell báo lỗi đó **theo dòng người dùng gõ**, nên thông báo chỉ vào `iex`
và đọc như thể one-liner sai.

`install.ps1` đặt `Set-ExecutionPolicy -Scope Process Bypass` trước khi gọi
setup. Scope process: không đổi gì ngoài lần chạy này, không cần quyền admin.

### Cài PowerShell 7 bằng tay rồi chạy lại → debloat chết

Xem [mục trên](#ngược-lại-debloat-bắt-buộc-51). Đây là hệ quả trực tiếp của lỗi
trước: cài pwsh 7 là phản xạ hợp lý khi one-liner lỗi, và nó làm hỏng bước khác.

### "Timeout" ngay đoạn check WSL, trên máy chưa cài gì

`wsl.exe` nằm sẵn trong `System32` **dù feature chưa bao giờ được bật**, nên
`Get-Command wsl` không chứng minh điều gì. Trên máy chưa có WSL, `wsl -l -q`
vẫn trả lời — nhưng có thể rất lâu, vì nó đi tìm gói Store trước. Màn hình đầu
tiên của setup là `detecting hardware...`, nên cả installer trông như treo trước
khi in được thứ gì hữu ích.

`detect.ps1` giờ hỏi service registry trước (`LxssManager` / `WSLService` —
tức thì), và chỉ khi có mới chạy `wsl.exe`, qua `Invoke-BoundedCommand` với
deadline 6 giây. `doctor.ps1` có bản sao cùng logic (nó phải chạy độc lập được).

### Chạy ngầm xong rồi mà phải nhấn Enter mới đi tiếp

Hai nguyên nhân, đã sửa cả hai:

**QuickEdit.** Mặc định của Windows console: click một cái vào cửa sổ là console
vào chế độ chọn text, và **mọi lệnh ghi của tiến trình bị chặn** cho tới khi ai
đó bấm Enter hoặc Esc. Giữa một bước winget 10 phút thì nó đọc đúng như treo.
`Initialize-Tui` tắt `ENABLE_QUICK_EDIT_MODE` (phải set kèm
`ENABLE_EXTENDED_FLAGS`, không thì bị bỏ qua).

**Câu hỏi vô hình.** `Invoke-Step` chuyển stdout/stderr của mỗi bước vào log, mà
stdin thì vẫn là console của installer. Script con nào hỏi gì — `Win11Debloat`
hỏi `Restart as Administrator? (y/n)` — thì câu hỏi biến mất vào log còn con trỏ
đứng chờ. Giờ mỗi bước được cấp một file rỗng làm stdin, nên prompt như vậy nhận
EOF thay vì nuốt mất phiên cài.

### LocalLLM không cài được vì "chưa khởi động được tiến trình yêu cầu"

`wsl --install` bật hai Windows feature, và **phải reboot** trước khi bất kỳ
distro nào chạy được. Bước `localllm` chạy ngay sau đó trong cùng phiên, cần một
distro đang chạy, và báo *failure* — trong khi sự thật chỉ là "chưa tới lúc".

`install-wsl.ps1` giờ trả về **3010** (quy ước installer của Windows: thành công,
cần reboot). `setup.ps1` đọc mã đó, đánh dấu bước wsl là Done kèm
`RESTART REQUIRED`, và **Skip** những bước cần distro đang chạy thay vì cho chúng
đâm đầu vào tường.

Rồi setup **tự chạy tiếp sau restart**, không phải gõ gì: các bước bị skip được ghi
vào `%LOCALAPPDATA%\Omacheese\resume.json`, một entry `RunOnce` gọi
`setup.ps1 -Resume` ở lần đăng nhập sau (mở một cửa sổ PowerShell, `-NoExit` để còn
đọc tổng kết). Mật khẩu Linux hỏi trước restart được giữ bằng DPAPI (chỉ user này
trên máy này giải mã được), file bị xoá ngay khi đọc, RunOnce thì Windows tự xoá
khi chạy — cả hai chỉ kích hoạt một lần. Cuối phiên, setup nói rõ cái gì cần
restart, vì sao, bước nào sẽ tự chạy tiếp, và hỏi `Restart Windows now?` (mặc định
**No**: một phím Enter lạc không được phép khởi động lại máy đang có việc dở).

Debloat cũng báo những setting chỉ có hiệu lực sau restart ("requires a reboot to
take full effect") — setup gom lại thành mục *Restart recommended* và cũng hỏi.

### Cài xong mà phải restart cả máy mới thấy gì chạy

Trước đây không có gì được khởi động sau khi cài: komorebi, whkd và yasb đều đợi
lần đăng nhập sau, PowerToys là thứ duy nhất tự lên (vì nó tự đăng ký autostart),
nên ấn tượng thành thật về một máy mới là setup **chẳng làm gì cả**.

Shortcut trong Startup lo mọi lần đăng nhập sau; `setup.ps1` giờ lo phiên bạn
đang ngồi: chạy `start-desktop.ps1` khi `wm` + `configs` đều xong, và mở Raycast
một lần khi module `raycast` được chọn (Store app cần đăng nhập thì mới dùng
được, cài xong mà không mở thì nó nằm đó không ai cấu hình).

Raycast là app **duy nhất** được mở: nó vô dụng cho tới khi wizard lần đầu (tài
khoản, hotkey, thư mục script) chạy xong, và wizard chỉ chạy khi app được mở. Nếu
có restart đang chờ thì chưa mở — nó được mang sang lần chạy resume. Mọi thứ khác
không bật lên màn hình; phần tổng kết in mục **Installed**: gói **mới cài** theo từng
nhóm (tên đọc được, gói Store hiện tên thay vì mã số), số gói đã có sẵn, và gói lỗi
nếu có. Chạy lại mà không cài thêm gì thì nó nói đúng như vậy. Số liệu lấy từ file
`packages-*.json` mà `install-windows.ps1` ghi vào thư mục log khi chạy dưới setup —
dòng `+ id` trong log in ra trước khi winget chạy nên không phân biệt được cài xong
hay chỉ mới thử.

PATH thì không sửa được từ bên ngoài: một tiến trình đọc PATH đúng một lần lúc
khởi động. Terminal đang chạy setup vẫn giữ PATH cũ, nên tổng kết ghi rõ là hãy
mở terminal mới để dùng những gì vừa cài — không phải reboot.

### WSL: không còn danh sách lệnh để gõ

Bước `distro` (`scripts/install-distro.ps1`) làm toàn bộ những gì trước đây nằm ở
cuối tổng kết: cài AlmaLinux-9, tạo user Linux trùng tên Windows (trước đây distro
cài `--no-launch` nên **không có user nào**, mọi shell chạy bằng root), đặt mật
khẩu, ghi `/etc/wsl.conf` với user đó làm mặc định, `wsl --terminate` để nạp, chạy
`install-almalinux.sh` (zsh làm shell, dev tools, config), cài agent trong WSL nếu
module `agents` cũng được chọn, và cài npiperelay bên Windows.

Mật khẩu được hỏi **trước bảng plan** (lúc duy nhất có console), chỉ khi account
chưa có mật khẩu; đi vào bước qua biến môi trường của một lần `Start-Process`,
tới `chpasswd` qua stdin — không bao giờ nằm trên command line hay ổ đĩa. Trong lúc
cài, user có sudo không mật khẩu **tạm thời** (`/etc/sudoers.d/90-omacheese-setup`),
gỡ trong `finally` dù bước thành công hay thất bại. Dưới `-Yes` không hỏi gì: account
được tạo chưa có mật khẩu, doctor báo, và lần chạy tương tác sau sẽ hỏi.

### Alacritty mất theme sau khi mở agent lần đầu

Chi tiết trong [`theming.md`](theming.md). Tóm tắt: `[keyboard] bindings = [...]`
là mảng định nghĩa tĩnh, mà `/terminal-setup` của Claude Code **nối thêm** một
block `[[keyboard.bindings]]` vào cuối file. TOML không cho mở rộng mảng tĩnh,
nên cả file thành lỗi parse (`alacritty.toml:104:12  duplicate key`) và Alacritty
rơi về mặc định. Config giờ viết dạng array-of-tables ngay từ đầu, và ship sẵn
binding Shift+Enter để agent không còn gì phải thêm.

### Config biến mất sau lần cài thứ hai

Repo từng được giải nén vào `%TEMP%\omacheese-install`, và `link-configs.ps1`
symlink mọi thứ vào đó. Xem
[`no-clone-install.md`](no-clone-install.md#repo-nằm-ở-đâu-sau-khi-cài).
