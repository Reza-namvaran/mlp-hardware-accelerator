# System architecture

## Block diagram

```
                    +------------------+
  pixels (Q8.8) --> | input buffer     |
                    +--------+---------+
                             |
                    +--------v---------+
                    | dense_layer H=16 |<-- ROM W1/B1
                    | MAC + ReLU       |
                    +--------+---------+
                             |
                    +--------v---------+
                    | hidden buffer    |
                    +--------+---------+
                             |
                    +--------v---------+
                    | dense_layer O=10 |<-- ROM W2/B2
                    | MAC (no ReLU)    |
                    +--------+---------+
                             |
                    +--------v---------+
                    | argmax           |--> class[3:0]
                    +------------------+
```

## Modules

| Module | Role |
|--------|------|
| `pkg_fixed` | Q8.8 types, mul truncate, saturate, ReLU |
| `pkg_weights` | Generated weight/bias ROM constants |
| `mac` | Clocked multiply-accumulate + bias clear |
| `relu` | Combinational ReLU |
| `neuron` | Serial MAC over one weight row |
| `dense_layer` | Walk a layer in groups of `N_PARALLEL` neurons (bonus: parallel MAC, see below) |
| `rom_weights` | Address decode into `pkg_weights`, `MAX_PARALLEL`-wide read ports |
| `mac8` | Bonus (dynamic precision): narrow-weight MAC variant, standalone (not wired into `mlp_top`) |
| `controller` | Layer orchestration FSM (documented twin of top FSM) |
| `mlp_top` | Buffers + layers + argmax + load handshake |
| `argmax` | Winner-take-all over 10 logits |

## Fixed-point policy

- Format: signed **Q8.8** (`DATA_WIDTH=16`, `FRAC_BITS=8`)
- MAC product: full `a*b` accumulated in **32-bit** `ACC_WIDTH`
- Bias added as `bias << FRAC_BITS` before truncation
- Result: arithmetic `>> FRAC_BITS` then saturate to int16
- Software reference in `python/quantization.py` matches this policy

## Handshake

1. Pulse `start`
2. Stream 784 pixels with `load_en` / `load_data`
3. Wait for `done`; read `class_out`

## Bonus: parallel MAC (`N_PARALLEL_HIDDEN`, `N_PARALLEL_OUTPUT` generics)

`mlp_top` exposes two generics controlling how many neurons of the hidden and
output layers run simultaneously (default **1/1** = original serial
baseline). `dense_layer` instantiates that many `neuron`/`mac` pairs and steps
through the layer in groups instead of one neuron at a time; `rom_weights`
serves one weight/bias read per active lane per cycle. Setting **16/10** runs
every neuron of both layers at once and cuts cycles/image from ~26 384 to
~2 406 (measured, see `results/bonus_parallel_mac.md`) with identical
classifications. See `docs/fsm.md` for the group-level cycle model.
