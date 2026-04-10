# Q5: syn directory usage and SRAM file checklist

## 1) Where to place files

Use this layout (already created):

- `syn/rtl/cnn/`:
  Put your project RTL here.
  Keep subfolders as:
  - `syn/rtl/cnn/conv/`
  - `syn/rtl/cnn/dwconv/`
  - `syn/rtl/cnn/pwconv/`
  - `syn/rtl/cnn/post_process/`
  - `syn/rtl/cnn/utils/`
  - top module at `syn/rtl/cnn/cnn.v`

- `syn/rtl/sram/`:
  Put SRAM Verilog macro models (`*.v`) here.
  Example:
  - `S018V3EBCDSP_X8Y4D96_PR.v`

- `SMIC18/lib/`:
  Standard-cell/IO timing libraries (`slow.lib`, `SP018W_V1p8_max.lib`, etc.).

- `SMIC18/mem/`:
  SRAM timing libraries (`*.lib`) for each SRAM macro size.

## 2) For your SRAM package (example: 32x96), which files are needed?

From `S018V3EBCDSP_X8Y4D96_PR.*` package:

Required for logic synthesis now:
- `S018V3EBCDSP_X8Y4D96_PR.v` (place in `syn/rtl/sram/`)
- one timing `.lib` corner file (place in `SMIC18/mem/`), usually:
  - `S018V3EBCDSP_X8Y4D96_PR_tt_1.8_25.lib` for initial bring-up
  - use `S018V3EBCDSP_X8Y4D96_PR_ss_1.62_125.lib` for worst-case timing closure

Needed for physical design later (not required for synthesis-only run):
- `S018V3EBCDSP_X8Y4D96_PR.lef` (macro abstract for place/route)
- `S018V3EBCDSP_X8Y4D96_PR.gds` (layout geometry for final stream-out)
- `S018V3EBCDSP_X8Y4D96_PR.cdl` (netlist for LVS/signoff)

Usually not needed for synthesis flow:
- `S018V3EBCDSP_X8Y4D96_PR.lvmemlib`
- `S018V3EBCDSP_X8Y4D96_PR.pdf`
- `log/`

## 3) How to run

From `syn/work/`:

```bash
csh
source setup.sh
zs_shell -f ../scripts/zs.tcl
```

After run:
- reports in `syn/reports/`
- netlist and output sdc in `syn/outputs/`
