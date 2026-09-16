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

Raycast **style được**, và repo có sẵn theme khớp với phần còn lại của desktop.

```powershell
./scripts/omarchy/omarchy-raycast-theme.ps1            # import vào Raycast
./scripts/omarchy/omarchy-raycast-theme.ps1 -ShowUrl   # chỉ in link ra
```

Hai điều cần biết trước:

- **Theme là tính năng trả phí của Raycast.** Changelog bản Windows nói nguyên
  văn: *"This feature is part of our paid offering but during the Beta period,
  we're excited to offer you full access for free."* Tức là đang free trong
  thời gian beta — một sự ưu ái của giai đoạn beta, không phải cam kết.
- **Raycast không import theme từ file.** Theme đi bằng deep link. Script trên
  dựng link `raycast://theme?...` từ
  `configs/raycast/omarchy-tokyo-night.json`, đúng format mà themes.ray.so dùng
  (`lib/url.ts` trong `raycast/theme-explorer`): mọi field trừ `colors` thành
  query param, rồi 12 màu nối bằng dấu phẩy **theo đúng thứ tự** — chúng là
  positional. Raycast sẽ hỏi xác nhận trước khi thêm.

File JSON là nguồn duy nhất; script sinh link từ nó nên link không thể lệch.

### Màu lấy từ đâu

11 trong 12 màu lấy thẳng từ config đang chạy, không phải bịa:

| Raycast | Hex | Có trong |
|---|---|---|
| `background` | `#1a1b26` | komorebi, yasb, alacritty |
| `backgroundSecondary` | `#24283b` | yasb |
| `text` | `#c0caf5` | komorebi, yasb, alacritty |
| `selection` | `#292e42` | yasb, alacritty |
| `loader` / `blue` | `#7aa2f7` | komorebi (border focus), yasb, alacritty |
| `red` | `#f7768e` | komorebi (locked), yasb, alacritty |
| `orange` | `#ff9e64` | yasb, alacritty |
| `yellow` | `#e0af68` | komorebi (floating), yasb, alacritty |
| `green` | `#9ece6a` | komorebi (monocle), yasb, alacritty |
| `magenta` | `#bb9af7` | komorebi (stack), yasb, alacritty |
| `purple` | `#9d7cd8` | **không có trong repo** — lấy từ Tokyo Night gốc |

`purple` là ngoại lệ duy nhất: schema của Raycast cần `purple` và `magenta`
riêng, mà repo chỉ dùng `#bb9af7`, nên `purple` lấy giá trị chuẩn của Tokyo
Night.

Nói cách khác: viền komorebi khi focus, chữ trên yasb, và nền Alacritty dùng
đúng những hex này — nên Raycast mở ra sẽ cùng tông thay vì lệch một nhịp.

## Kiểm tra

`doctor.ps1` và CI đều validate metadata header, vì header sai **không báo lỗi**
— lệnh chỉ đơn giản là không xuất hiện trong Raycast, kiểu hỏng khó chịu nhất.

```
raycast script commands
  PASS  7 script commands valid
```
