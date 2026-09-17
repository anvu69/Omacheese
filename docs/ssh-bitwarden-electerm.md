# SSH: Bitwarden agent, WSL, electerm

## Kiến trúc

```text
Bitwarden Desktop (Windows)
   │  giữ private key, ký challenge
   ├─ \\.\pipe\openssh-ssh-agent ──► ssh.exe (Windows), electerm
   └─ npiperelay + socat ──────────► ~/.ssh/agent.sock ──► ssh (WSL), tmux, ansible
```

Private key không bao giờ rời vault. Client chỉ gửi challenge cho agent ký.

---

## 1. Bật SSH agent trong Bitwarden

1. Bitwarden Desktop → **Settings** → bật **SSH agent**.
2. Tạo/import key dưới dạng item loại **SSH key**.
3. **Bắt buộc**: `services.msc` → **OpenSSH Authentication Agent** →
   Startup type = **Disabled** → Stop. Module `desktop` của setup tự làm bước
   này (`scripts/disable-openssh-agent.ps1`, một lần UAC, bỏ qua nếu đã Disabled),
   và mở sẵn Bitwarden ở cuối để bạn làm bước 1-2.

Bước 3 không phải tùy chọn. Bitwarden phục vụ đúng cái named pipe
`\\.\pipe\openssh-ssh-agent` mà service của Windows cũng đòi; để cả hai chạy
thì cái nào giành được trước sẽ thắng, và triệu chứng là "key lúc có lúc không".

Kiểm tra:

```powershell
ssh-add -l          # phải liệt kê key trong vault
```

---

## 2. Đưa agent vào WSL

Đây là mảng repo này **thiếu hoàn toàn** trước đây: tài liệu mô tả luồng hằng
ngày là Alacritty → WSL2 → tmux → ssh, nhưng agent chạy bên Windows và nói
chuyện qua named pipe, còn `ssh` trong WSL cần unix socket. Không có cầu nối
thì `ssh` trong WSL **không có key nào cả**.

Cầu nối là `npiperelay.exe` + `socat`:

```powershell
# Windows
winget install --id albertony.npiperelay -e
```

```bash
# WSL
sudo dnf install -y socat
```

`configs/wsl/ssh-agent-bridge.sh` lo phần còn lại và được `zshrc` source sẵn.
Nó dựng socket, export `SSH_AUTH_SOCK`, và tự dọn socket cũ còn sót sau reboot.

Kiểm tra trong WSL:

```bash
ssh-add -l        # cùng danh sách key như bên Windows
sshkeys           # alias của lệnh trên
bw_agent_status   # chẩn đoán chi tiết
bw_agent_restart  # dựng lại cầu nối
```

Nếu rỗng: Bitwarden có đang chạy và đã unlock chưa? Agent đã bật chưa?
`npiperelay.exe` có trong PATH của Windows không?

---

## 3. `IdentitiesOnly yes`

`configs/ssh/config.example` đặt `IdentitiesOnly yes`. Bản cũ để `no`.

Với agent giữ nhiều key, client sẽ chào **từng key một** cho tới khi server
nhận. Server mặc định `MaxAuthTries 6`, nên khi vault có hơn vài key, kết nối
bắt đầu fail bằng `Too many authentication failures` — và key nào bị từ chối
phụ thuộc thứ tự, nên nó trông như lỗi chập chờn.

`IdentitiesOnly yes` + `IdentityFile` trỏ vào **public key** khiến client chỉ
chào đúng một key. Với agent, public key là đủ để chọn private key tương ứng.

---

## 4. Jump server

Ưu tiên `ProxyJump`, tránh `ForwardAgent yes`:

```sshconfig
Host prod-web-01
  HostName 10.10.10.11
  User almalinux
  ProxyJump jump-main
```

`ProxyJump` tạo tunnel xuyên qua bastion mà **không** expose agent socket cho
nó. `ForwardAgent yes` thì ngược lại: trong suốt phiên của bạn, root trên
bastion có thể dùng agent để mạo danh bạn sang máy khác.

`config.example` cũng bật `ControlMaster`, nên scp/rsync/tmux split tới cùng
host dùng lại một TCP connection — gần như tức thì.

---

## 5. electerm

Dùng electerm cho: quản lý session GUI, SFTP, tunnel, việc admin lẻ tẻ.

Dùng Alacritty + tmux + ssh cho công việc terminal hằng ngày.

electerm đọc được `~/.ssh/config`, nên giữ OpenSSH config làm nguồn sự thật
sẽ tránh khóa chặt vào một tool: cùng file đó chạy cho `ssh`, `scp`, `rsync`,
`ansible`, và cả `ss`/`sst` picker trong repo này.

---

## Chẩn đoán nhanh

```powershell
./scripts/doctor.ps1     # kiểm tra service, npiperelay, cầu nối
ssh -v <host>            # xem key nào được chào
```

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| `ssh-add -l` rỗng trên Windows | Bitwarden chưa unlock, hoặc agent chưa bật |
| Windows ổn, WSL rỗng | thiếu npiperelay/socat, hoặc socket cũ → `bw_agent_restart` |
| `Too many authentication failures` | thiếu `IdentitiesOnly yes` |
| Key lúc có lúc không | service OpenSSH Authentication Agent chưa Disabled |
