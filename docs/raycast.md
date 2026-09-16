# Raycast

Raycast là launcher cho macOS, và từ 2025 có bản Windows. Repo này ship sẵn một
bộ **Script Commands** để các hành động của desktop (layout, workspace, toggle,
agent, config) gọi được thẳng từ Raycast.

Đây là **tuỳ chọn**. Menu `SUPER + SPACE` không cần Raycast và không bao giờ
cần — xem [`keybindings.md`](keybindings.md).

## Cài

```powershell
./scripts/setup.ps1            # tick module "raycast"
# hoặc
winget install --id 9PFXXSHC64H3 --source msstore --accept-source-agreements
```

Vài điểm cần biết trước khi quyết định:

- **Không có MSI độc lập.** Link tải trên trang chủ (`ray.so/download-windows`)
  redirect sang `get.microsoft.com/installer/download/9PFXXSHC64H3` và trả về
  `Raycast Installer.exe` — đó là **stub installer của Microsoft Store**, vẫn kéo
  gói MSIX từ Store về. Nó là app GUI nên không cài im lặng được; đường tự động
  hoá duy nhất là `winget --source msstore`.
- **Có thể phải đăng nhập tài khoản Raycast.** Tài liệu nói cần đăng nhập cùng
  một tài khoản trên mỗi thiết bị để đồng bộ, nhưng không nói rõ bản free trên
  Windows có *bắt buộc* hay không. Với máy cài mới hàng loạt thì đây là bước thủ
  công cần tính đến.
- **Window Management của Raycast có thể đụng komorebi.** Tắt nó trong Settings.

## Trỏ Raycast vào thư mục script

`link-configs.ps1` cài các script vào:

```
~/.config/omarchy/raycast/
```

Bước cuối phải làm bằng tay, vì Raycast giữ cấu hình trong store riêng của nó
chứ không phải file trên đĩa:

**Raycast → Settings → Extensions → Script Commands → Add Script Directory**
→ chọn `~/.config/omarchy/raycast`

## Có gì

Bảy lệnh, gộp lại bằng dropdown thay vì đẻ ra 70 lệnh rời — Raycast tìm theo
tên nên ít mà rõ vẫn hơn nhiều mà nhiễu.

| Lệnh | Dropdown |
|---|---|
| `Layout` | BSP, Columns, Rows, Grid, Ultrawide, Scrolling, next/prev, flip, promote, retile, reload |
| `Toggle` | Scrolling mode, status bar, pause, tiling, float, monocle, transparency, title bars… |
| `Workspace` | 10 workspace × (focus / move / send) |
| `Terminal` | PowerShell, WSL+tmux, Neovim, btop, lazygit |
| `Agent` | default / WSL / pick / list, kèm ô prompt tuỳ chọn |
| `Edit Config` | whkdrc, komorebi, yasb, alacritty, profile, ssh, git, wsl, scrolling |
| `Desktop` | restart stack, cheatsheet, menu, stop komorebi, WSL shutdown |

Tất cả đặt `mode silent`, nên Raycast đóng lại và hiện một dòng HUD.

Ba thứ cố tình **không** đưa vào:

- **Lock / Sleep / Restart / Shut down** — Raycast đã có sẵn, thêm nữa chỉ nhiễu.
- **`-Yolo`** (agent bỏ qua mọi permission prompt) — nó chỉ cách "Default agent"
  một phím trong dropdown, quá dễ chọn nhầm cho một thứ chạy được mọi lệnh với
  SSH agent và work tree của bạn. Nó nằm trong menu `SUPER+SPACE`, sau một trang
  xác nhận.
- **Workspace đọc từ state sống.** Metadata của Raycast là tĩnh nên dropdown
  workspace phải hardcode. Nếu đổi tên workspace trong `komorebi.json` thì sửa
  cả `omarchy-workspace.ps1`. Menu `SUPER+SPACE` thì đọc trực tiếp từ komorebi
  nên không lệch được.

## Scrolling mode

Vào Scrolling qua Raycast vẫn có phần hé bình thường: `omarchy-scroll-daemon`
theo dõi mọi workspace và tự áp offset bất kể vào bằng đường nào. Đã kiểm chứng
— chạy `Layout → Scrolling` từ Raycast cho ra offset `L0/R228`, đúng như khi bấm
`SUPER+CTRL+S`.

## Theme

Raycast **style được**, và nó dùng chung palette với cả desktop — không phải
một chỗ chỉnh màu riêng.

```powershell
./scripts/omarchy/omarchy-theme.ps1 -Set catppuccin     # đổi cả desktop
./scripts/omarchy/omarchy-raycast-theme.ps1             # đẩy sang Raycast
```

`omarchy-theme.ps1` render ra `~/.config/omarchy/raycast-theme.json` mỗi lần đổi
theme; `omarchy-raycast-theme.ps1` dựng deep link từ file đó. Nên Raycast luôn
theo đúng màu mà komorebi, yasb và Alacritty đang dùng. Chi tiết palette:
[`theming.md`](theming.md).

Hai điều cần biết:

- **Theme là tính năng trả phí của Raycast.** Changelog bản Windows nói nguyên
  văn: *"This feature is part of our paid offering but during the Beta period,
  we're excited to offer you full access for free."* — đang free trong thời gian
  beta, nhưng đó là ưu ái giai đoạn beta, không phải cam kết.
- **Raycast không import theme từ file.** Theme đi bằng deep link
  `raycast://theme?...`, đúng format mà themes.ray.so dùng (`lib/url.ts` trong
  `raycast/theme-explorer`): mọi field trừ `colors` thành query param, rồi 12 màu
  nối bằng phẩy **theo đúng thứ tự** — chúng là positional. Raycast hỏi xác nhận
  trước khi thêm, nên bước cuối là một cú click.

Map từ palette 26 key của Omarchy sang 12 slot của Raycast:

| Raycast | ← palette |
|---|---|
| `background` | `background` |
| `backgroundSecondary` | `lighter_background` |
| `text` | `bright_foreground` |
| `selection` | `selection` |
| `loader` | `accent` |
| `red` `orange` `yellow` `green` `blue` | cùng tên |
| `purple` | `magenta` |
| `magenta` | `bright_magenta` |

## Kiểm tra

`doctor.ps1` và CI đều validate metadata header, vì header sai **không báo lỗi**
— lệnh chỉ đơn giản là không xuất hiện trong Raycast, kiểu hỏng khó chịu nhất.

```
raycast script commands
  PASS  7 script commands valid
```
