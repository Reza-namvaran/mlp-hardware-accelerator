# Toolchain

## Python (uv + 3.11 + PyTorch)

```bash
uv python pin 3.11
uv sync
uv run python core/train.py
```

Pinned in `.python-version` and `pyproject.toml` (`requires-python = ">=3.11,<3.12"`).

If `download.pytorch.org` is blocked on your network, install from PyPI (may pull CUDA wheels; still runs on CPU):

```bash
uv pip install torch torchvision numpy matplotlib pytest
```

Prefer CPU wheels when reachable:

```bash
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
uv pip install numpy matplotlib pytest
```

## VHDL simulation

| Tool | Role |
|------|------|
| GHDL | Analyze / elaborate / run |
| GTKWave | View `.ghw` waveforms |

### Install

```bash
# Arch
sudo pacman -S ghdl gtkwave

# Debian / Ubuntu
sudo apt install ghdl gtkwave
```

### Smoke check

```bash
chmod +x scripts/sim.sh
./scripts/sim.sh unit
```

### Usage

```bash
./scripts/sim.sh unit
./scripts/sim.sh top
WAVE=1 ./scripts/sim.sh top --wave
```

## Optional synthesis

Open `vhdl/rtl/mlp_top.vhd` (+ deps) in Vivado/Quartus; store reports under `results/synth/`.
