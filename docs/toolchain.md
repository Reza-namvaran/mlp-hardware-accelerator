# Toolchain

## VHDL simulation

| Tool | Role |
|------|------|
| GHDL | Analyze / elaborate / run |
| GTKWave | View waveforms |

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
./scripts/sim.sh pkg
```