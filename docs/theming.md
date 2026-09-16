# Theming

Một palette, áp cho tất cả.

```powershell
./scripts/omacheese/omacheese-theme.ps1 -List
./scripts/omacheese/omacheese-theme.ps1 -Set catppuccin
./scripts/omacheese/omacheese-theme.ps1 -Current
```

Trước đây màu nằm rải rác thành hex literal ở bốn file khác nhau — đổi theme
nghĩa là find-and-replace qua komorebi, yasb, Alacritty và menu, và chúng lệch
nhau dần. Giờ chỉ có một palette, config được render ra từ template.

## Palette

Palette lấy **nguyên văn** từ Omarchy (`omacom/omarchy`,
`themes/<name>/colors.toml`), nên bất kỳ theme nào trong 22 theme của nó cũng
thả vào `configs/theme/` là dùng được, không cần dịch. Mọi theme đều khai báo
đúng 26 key giống nhau — đó là thứ làm chúng thay thế được cho nhau:

```
mode
accent  selection  muted
background  dark_background  darker_background  lighter_background
foreground  dark_foreground  light_foreground  bright_foreground
red  yellow  orange  green  cyan  blue  magenta  brown
bright_red  bright_yellow  bright_green  bright_cyan  bright_blue  bright_magenta
```

Repo ship sẵn `tokyo-night` và `catppuccin`. Thêm theme khác:

```powershell
curl -o configs/theme/gruvbox.toml `
  https://raw.githubusercontent.com/omacom/omarchy/quattro/themes/gruvbox/colors.toml
./scripts/omacheese/omacheese-theme.ps1 -Set gruvbox
```

## Template

Template là **chính config thật**, chỉ thay hex literal bằng `{{token}}`. Mọi
thứ khác — `min-width` của yasb, font stack của Alacritty, rule của komorebi —
giữ nguyên từng byte. Nên đổi theme không thể làm vỡ layout.

| Template | Render ra |
|---|---|
| `configs/komorebi/komorebi.json.tmpl` | `~/.config/komorebi/komorebi.json` |
| `configs/yasb/styles.css.tmpl` | `~/.config/yasb/styles.css` |
| `configs/alacritty/alacritty.toml.tmpl` | `%APPDATA%/alacritty/alacritty.toml` |

Hai thứ không dùng template:

- **Menu `SUPER+SPACE`** đọc palette lúc chạy và thay màu trong XAML trước khi
  parse. Nó là script, không phải file config, nên render ra đĩa sẽ thừa.
- **Raycast** có schema riêng đúng 12 màu, nên được *dựng* chứ không render —
  xem [`raycast.md`](raycast.md).

## Đã kiểm chứng

Đổi `tokyo-night` ↔ `catppuccin` trên máy thật, đếm lại toàn bộ giá trị màu
trên đĩa:

| File | Số màu | Đúng palette mới | Sót lại palette cũ |
|---|---|---|---|
| komorebi.json | 9 | 9 | **0** |
| styles.css | 98 | 98 | **0** |
| alacritty.toml | 23 | 23 | **0** |
| raycast-theme.json | 12 | 12 | **0** |

komorebi `reload-configuration` nhận file mới, yasb tự restart, Alacritty ăn màu
ở cửa sổ kế tiếp.

## Khi nào hỏng, và hỏng thế nào

Nếu palette thiếu một key mà template có dùng, generator **để nguyên
`{{token}}`** và in warning, thay vì đẩy ra chuỗi rỗng. Lý do: chuỗi rỗng render
thành màu đen và trông như lỗi style, còn `{{accent}}` nằm chình ình thì biết
ngay là thiếu key.

Cả `doctor.ps1` lẫn CI đều bắt chuyện này:

```
theme
  PASS  theme 'tokyo-night'
  PASS  rendered configs have no unresolved tokens
```

CI còn kiểm hai thứ nữa:

- **mọi token trong template phải có trong mọi palette** — nếu không, đổi sang
  theme đó sẽ để lại `{{token}}` trong config;
- **render template bằng `tokyo-night` phải ra đúng file đã commit** — để
  template không lệch khỏi config mà nó sinh ra.
