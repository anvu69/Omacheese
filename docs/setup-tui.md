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
+- windows11-dev-poweruser ------------------------------------------+
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
| `full` | + agents, wsl |
| `everything` | + localllm (nếu phần cứng cho phép) |

`-DryRun` in kế hoạch rồi dừng, không đổi gì.

---

## Gating theo phần cứng

`scripts/lib/detect.ps1` dò một lần, mọi module hỏi kết quả đó.

| Module | Yêu cầu |
|---|---|
| core, cli, wm, desktop, agents | winget |
| wsl | Windows 10 2004+ và **virtualisation bật trong BIOS** |
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
%USERPROFILE%\.config\windows11-dev-poweruser\backups\<timestamp>\
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
|   C:\Users\ban\.config\windows11-dev-poweruser\backups\20260916-013020|
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
| Dùng cho | `setup.ps1` và mọi script cài | profile hằng ngày, helper Omarchy |
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

### Helper Omarchy không phụ thuộc pwsh

whkdrc gọi `omarchy-run.cmd`, chọn pwsh nếu có, không thì `powershell.exe`.
Trước đây 11 binding hardcode `pwsh` và im lặng không làm gì khi bỏ qua `core`.

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
