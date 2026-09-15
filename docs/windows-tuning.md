# Debloat và tối ưu Windows cho tiling desktop

```powershell
./scripts/debloat-windows.ps1 -DryRun      # xem sẽ chạy gì
./scripts/debloat-windows.ps1              # áp dụng settings
./scripts/debloat-windows.ps1 -RemoveApps  # gỡ luôn app bundled
```

Wrapper quanh [Win11Debloat](https://github.com/Raphire/Win11Debloat) thay vì
viết lại — nó được maintain tốt, 57k sao, và đã biết sẵn các registry path.
Phần repo này thêm vào:

- **pin version** (`2026.08.24`) → chạy hôm nay giống chạy tháng sau
- **profile version-control được**: `configs/windows/debloat.json`, review được
  trong PR thay vì bấm qua GUI
- vài tweak Win11Debloat không có
- **validate**: mọi flag trong profile được đối chiếu với `param()` thật của
  Win11Debloat (117 tham số) — cùng loại lỗi với winget ID sai

Settings đều reversible (Win11Debloat tạo restore point trước). **Gỡ app thì
không**, nên nó nằm sau `-RemoveApps` riêng.

---

## Cái gì thật sự đánh nhau với komorebi

Đây là phần quan trọng nhất và cũng là phần dễ bị bỏ qua nhất:

| Setting | Vấn đề |
|---|---|
| `DisableWindowSnapping` | Windows tự kéo/thả cửa sổ vào nửa màn hình — giành quyền đặt cửa sổ với komorebi |
| `DisableSnapAssist` | Popup "chọn cửa sổ cho nửa còn lại" bật lên giữa lúc komorebi đang tile |
| `DisableSnapLayouts` | Fly-out khi hover nút maximize |
| `HideTaskview` | Nút cho một tính năng workspace mà komorebi đã thay thế |
| `HideTabsInAltTab` | Alt+Tab đã remap sang `komorebic cycle-focus`; tab của app chỉ là nhiễu |

Trên máy này, **ba cái snapping đầu vẫn đang bật** — `doctor.ps1` sẽ báo.

---

## Taskbar

yasb mới là bar thật (reserve chỗ qua AppBar API). Taskbar Windows bị rút gọn
tối đa:

| Setting | Giá trị |
|---|---|
| `TaskbarAlignLeft` | icon về trái |
| `HideSearchTb` | bỏ ô search |
| `HideTaskview` | bỏ Task View |
| `HideChat` | bỏ Chat/Meet |
| `DisableWidgets` | tắt widget service |
| `CombineTaskbarAlways` | gộp button, bỏ label |
| `EnableEndTask` | thêm "End task" vào menu chuột phải |

Cộng thêm (script tự làm, Win11Debloat không có):

- **auto-hide taskbar** — sửa bit `0x08` của `StuckRects3\Settings[8]`
- tắt News & interests
- tắt search highlights

> Auto-hide thay vì ẩn hẳn: taskbar vẫn là nơi hệ thống vẽ tray icon và
> notification. Ẩn hoàn toàn sẽ mất cả hai.

---

## Explorer, privacy, AI, system

| Nhóm | Gồm |
|---|---|
| Explorer | đuôi file thật, file ẩn, mở vào This PC, bỏ Gallery, drive letter trước, **context menu kiểu Win10** (bỏ "Show more options") |
| Privacy | telemetry, Bing trong search, suggestion, lockscreen tips, quảng cáo 365/Edge, Find My Device |
| AI | Copilot, Recall, Click to Do, AI trong Edge/Paint/Notepad, `WSAIFabricSvc` về manual |
| System | dark mode (khớp Tokyo Night), **tắt mouse acceleration**, Sticky Keys, **tắt Fast Startup**, Delivery Optimization, chặn tự reboot sau update |

Hai cái đáng nói:

**Mouse acceleration** (`1,6,10` trên máy này) — "Enhance pointer precision"
làm con trỏ đi quãng đường khác nhau với cùng khoảng cách chuột vật lý. Tắt đi
thì cơ bắp tay mới học được.

**Fast Startup** — nó không shutdown thật mà hibernate kernel. Sau update
driver hoặc khi WSL2/GPU dở chứng, "shutdown rồi bật lại" của bạn thực ra
không phải shutdown. Tắt là điều kiện cần để debug được.

---

## AI của Windows ≠ coding agent

`debloat.json` tắt Copilot/Recall/Click to Do — đó là AI **gắn vào OS**.

Không liên quan gì tới Claude Code / Codex mà repo cài — xem
[`docs/ai-stack.md`](ai-stack.md). Tắt cái trước không ảnh hưởng cái sau.

---

## App bị gỡ (chỉ khi `-RemoveApps`)

Clipchamp, Bing News/Weather/Search, Xbox (app + overlay + TCUI + identity),
Solitaire, Office Hub, People, Power Automate, To Do, Feedback Hub, Maps,
Media Player/Movies (Zune*), Family, Teams.

Danh sách nằm trong `$AppsToRemove` ở `scripts/debloat-windows.ps1`. Không gỡ
Edge (`-ForceRemoveEdge` tồn tại nhưng hay làm hỏng update; bật thủ công nếu
bạn thật sự muốn).

---

## Kiểm tra

```powershell
./scripts/doctor.ps1      # mục "windows tuning"
```

Sau khi áp dụng, restart Explorer:

```powershell
Stop-Process -Name explorer -Force
```

## Hoàn tác

Win11Debloat tạo restore point trước (`CreateRestorePoint` trong profile). Hầu
hết flag có flag ngược (`-ShowSearchIconTb`, `-EnableDesktopSpotlight`…). App
đã gỡ thì cài lại từ Microsoft Store.
