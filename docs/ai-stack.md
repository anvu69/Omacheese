# AI stack: coding agents, Docker/GPU in WSL, vLLM

Hai phần tách biệt:

- **Coding agents** (Claude Code, Codex…) — chạy trên Windows, quản lý kiểu Omarchy.
- **Model serving / fine-tuning** — chạy trong WSL2 + Docker + GPU.

---

## Phần 1 — Coding agents

Port từ `omarchy-agent` / `omarchy-default-agent` của Omarchy: chọn một agent
mặc định, rồi một phím mở nó.

```powershell
./scripts/install-windows.ps1 -Groups ai      # Claude Code, Codex, fnm, uv
omarchy-default-agent.ps1 -List               # xem có gì
omarchy-default-agent.ps1 claude              # đặt mặc định
```

| Phím | Việc |
|---|---|
| `SUPER + A` | Mở agent mặc định |
| `SUPER + SHIFT + CTRL + A` | Chọn agent (chord của Omarchy) |
| `SUPER + ALT + A` | Mở agent bên trong WSL |
| `SUPER + SPACE` → Agents | Menu đầy đủ |

Agent hỗ trợ: `claude`, `codex`, `gemini`, `opencode`, `copilot`, `cursor`,
`crush`. Thêm agent mới bằng cách sửa `$script:Agents` trong
`scripts/omarchy/omarchy-default-agent.ps1`.

### Một chỗ cố tình khác Omarchy

Omarchy truyền cờ bỏ-qua-quyền (`--dangerously-skip-permissions`,
`--yolo`…) **mỗi lần** launch từ keybinding — hợp lý trên một máy Arch chuyên
dụng.

Ở đây nó là **opt-in** (`-Yolo`). Máy này giữ Bitwarden SSH agent và toàn bộ
work tree; một agent chạy không giám sát với full approval chạm tới được cả
hai. Menu có mục `-Yolo` riêng và hỏi xác nhận.

---

## Phần 2 — Docker + GPU trong WSL

```bash
bash ./scripts/install-docker-wsl.sh
bash ./scripts/install-docker-wsl.sh --check    # chỉ kiểm tra
```

Script cài **docker-ce native trong AlmaLinux**, không phải Docker Desktop.

### Tại sao không Docker Desktop

Docker Desktop vẫn dùng được — nếu bạn đang phụ thuộc nó thì chỉ cần bật WSL
integration cho distro này thay vì chạy script. Hai lý do repo chọn cài engine
trực tiếp:

1. `configs/wsl/wsl.conf` đặt `appendWindowsPath=false`. **Hiện tại** `docker`
   trong AlmaLinux trỏ tới `/mnt/c/.../docker.exe` — đó chỉ là PATH của Windows
   rò sang, WSL integration **chưa hề bật**. Khi tắt appendWindowsPath, chỗ rò
   đó biến mất và distro không còn docker nào.
2. GPU container cần NVIDIA Container Toolkit gắn vào daemon bạn kiểm soát, và
   systemd đã là PID 1 sẵn.

`doctor.ps1` phân biệt được ba trạng thái này (rò PATH / cài thật / không có).

### Yêu cầu

| Thứ | Trạng thái trên máy này |
|---|---|
| Driver NVIDIA trên **Windows** | ✅ 616.92 (không bao giờ cài driver *trong* WSL) |
| `/dev/dxg` | ✅ |
| `/usr/lib/wsl/lib/libcuda.so.1` | ✅ |
| systemd PID 1 | ✅ |
| NVIDIA Container Toolkit | ❌ script sẽ cài |

---

## Phần 3 — vLLM

> **vLLM không train model.** Nó là inference server (OpenAI-compatible API).
> Bạn nhắc "training model qua vLLM" — phần train nằm ở
> [Phần 4](#phần-4--fine-tuning) bên dưới. Luồng thường dùng là: fine-tune bằng
> Axolotl → merge adapter → **serve** kết quả bằng vLLM.

```bash
cd ~/.config/ai
cp .env.example .env        # điền HF_TOKEN nếu dùng model gated
docker compose -f docker-compose.vllm.yml up -d
curl http://localhost:8000/v1/models
```

Nhờ `networkingMode=mirrored` trong `.wslconfig`, `localhost:8000` truy cập
được **từ cả Windows lẫn WSL**, không cần port-proxy.

### Chọn model cho 16 GB (RTX 4080 SUPER)

VRAM là ràng buộc cứng. Weight chỉ là một phần — còn KV cache cho context.

| Cấu hình | VRAM weights | Nhận xét |
|---|---|---|
| 8B fp16 | ~16 GB | **không vừa** — không còn chỗ cho KV cache |
| **8B fp8** | **~8 GB** | ✅ mặc định. Ada (compute 8.9) có FP8 native |
| 14B AWQ/GPTQ 4-bit | ~9 GB | ✅ được, context ngắn hơn |
| 3–4B fp16 | ~7 GB | ✅ thoải mái, context dài |
| 32B bất kỳ | ≥20 GB | ❌ cần GPU khác |

Đổi model không cần sửa compose — sửa `.env`:

```bash
MODEL=Qwen/Qwen3-8B
QUANT=fp8
MAX_LEN=16384
GPU_UTIL=0.90
```

Hết VRAM thì giảm `MAX_LEN` trước, rồi mới tới `GPU_UTIL`.

### Nối vào coding agent

vLLM expose OpenAI API nên agent nào nhận `OPENAI_BASE_URL` đều trỏ vào được:

```bash
export OPENAI_BASE_URL=http://localhost:8000/v1
export OPENAI_API_KEY=dummy      # vLLM không kiểm tra trừ khi bật --api-key
```

---

## Phần 4 — Fine-tuning

```bash
cd ~/.config/ai
docker compose -f docker-compose.finetune.yml run --rm train
```

Dùng [Axolotl](https://github.com/axolotl-ai-cloud/axolotl) (bọc PEFT/TRL/
bitsandbytes, cấu hình bằng YAML).

Với 16 GB, mục tiêu thực tế là **QLoRA** (base 4-bit + LoRA adapter):

| Việc | 16 GB? |
|---|---|
| QLoRA 7–8B, seq 2048, batch 1 + grad accum | ✅ ~12–14 GB |
| QLoRA 13–14B, seq 1024 | ⚠️ sát nút |
| Full fine-tune > 1–2B | ❌ thuê GPU |

Cả hai compose file dùng chung project `ai` nên **chia sẻ cache Hugging Face** —
model tải cho train không phải tải lại cho serve.

Vòng lặp:

```text
axolotl train cfg.yml  →  merge adapter  →  MODEL=/workspace/merged trong .env  →  vLLM
```

Giữ cache và dataset trên **filesystem Linux** (`~`), đừng để `/mnt/d`: qua 9p
mỗi lần load chậm hơn nhiều lần.

---

## Chẩn đoán

```powershell
./scripts/doctor.ps1        # phần "wsl / docker" và "coding agents"
```

```bash
bash ./scripts/install-docker-wsl.sh --check
docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubi9 nvidia-smi
docker compose -f docker-compose.vllm.yml logs -f vllm
```

| Triệu chứng | Nguyên nhân |
|---|---|
| `docker: permission denied` | chưa vào group docker → `wsl --shutdown` |
| container không thấy GPU | thiếu nvidia-container-toolkit, hoặc chưa `nvidia-ctk runtime configure` |
| `CUDA out of memory` khi khởi động | giảm `MAX_LEN`, rồi `GPU_UTIL` |
| model tải rất chậm | cache đang nằm trên `/mnt/*` thay vì `~` |
| `401` khi tải model | model gated, thiếu `HF_TOKEN` trong `.env` |
