# PicoSoC with Lightweight Cryptographic Accelerators

This repository provides a complete System-on-Chip (SoC) based on the **PicoRV32** RISC-V CPU, featuring high-speed hardware accelerators for **TinyJAMBU**, **Xoodyak**, and **GIFT-COFB** integrated under a unified register map interface. The design is optimized for area-constrained ASIC implementations using the **OpenLane2** physical design flow.

---

## 1. Project Overview

The project extends the standard PicoSoC architecture by integrating a dedicated **Crypto Layer** on the system bus. This allows the PicoRV32 core to offload intensive cryptographic operations to hardware, significantly improving performance and energy efficiency compared to software-only implementations.

### Key Components

- **CPU**: PicoRV32 (RV32I) - A size-optimized RISC-V implementation.
- **Interconnect**: AXI4-Lite system bus bridged to an APB peripheral bus.
- **Memory**: 4 KB Boot BRAM (preloaded with bootloader) and 16 KB Application BRAM (on AXI).
- **Crypto Accelerators**:
  - **TinyJAMBU-128**: Lightweight AEAD (Authenticated Encryption with Associated Data) accelerator.
  - **Xoodyak**: Area-optimized Keyed-only AEAD (Hash mode removed for ASIC efficiency).
  - **GIFT-COFB**: Block-cipher-based NIST Lightweight Cryptography (LWC) finalist algorithm.
- **Peripherals**: 115200 Baud UART, SD Card SPI Master, GPIO / Output LED register, Input Pin registers (switches & buttons).

---

## 2. System Architecture

### Memory Map

The system uses a 32-bit address space. All peripherals and memories are memory-mapped to make software interactions straightforward.

| Address Range | Peripheral | Description |
| :--- | :--- | :--- |
| `0x0000_0000` - `0x0000_0FFF` | **Boot ROM** | 4 KB Bootloader BRAM (Software pre-loaded) |
| `0x0001_0000` - `0x0001_3FFF` | **Main RAM** | 16 KB Application Memory BRAM (Read/Write, AXI) |
| `0x1000_0000` | **LED Output** | `out_byte` output register (Write-only) |
| `0x1000_0004` - `0x1000_0010` | **UART** | TX Data (`0x04`), RX Data (`0x08`), Status (`0x0C`), Baud Divider (`0x10`) |
| `0x2000_0000` - `0x2000_0004` | **Board Inputs** | Board Switches (`0x00`), Board Buttons (`0x04`) (Read-only) |
| `0x3000_0000` - `0x3000_00B7` | **AEAD Cluster** | Unified AEAD Accelerator Wrapper (TinyJAMBU, Xoodyak, GIFT-COFB) |
| `0x6000_0000` - `0x6000_000C` | **SD SPI Master**| SPI Interface for SD card raw sector reads |

---

## 3. Cryptographic Hardware Accelerators

All three crypto cores are managed by a unified registers and multiplexer interface inside `crypto_cluster.v` mapped at `0x3000_0000`.

### Register Map (`AEAD_BASE = 0x3000_0000`)

| Offset | Register Name | Description |
| :--- | :--- | :--- |
| `0x00` | `AEAD_CTRL` | Control / Status register:<br>- `[1:0]` Algorithm Select (`00`=TinyJAMBU, `01`=Xoodyak, `10`=GIFT-COFB)<br>- `[2]` Start Pulse (write `1` to trigger, auto-clears)<br>- `[3]` Decrypt Mode (`0`=Encrypt, `1`=Decrypt)<br>- `[6]` Done sticky bit (read-only)<br>- `[7]` Valid sticky bit (read-only) |
| `0x04` - `0x10` | `AEAD_KEY[0:3]` | 128-bit Key registers (4 words) |
| `0x14` - `0x20` | `AEAD_NONCE[0:3]`| 128-bit Nonce registers (4 words, TinyJAMBU uses 96-bit `[95:0]`) |
| `0x24` - `0x30` | `AEAD_AD[0:3]` | 128-bit Associated Data input registers |
| `0x34` - `0x40` | `AEAD_DIN[0:3]` | 128-bit Plaintext / Ciphertext input registers |
| `0x44` - `0x50` | `AEAD_TAGIN[0:3]`| 128-bit Input Tag registers (TinyJAMBU uses 64-bit `[63:0]`) |
| `0x54` | `AEAD_AD_LEN` | 8-bit Associated Data length (bytes) |
| `0x58` | `AEAD_DAT_LEN` | 8-bit Data / Plaintext length (bytes) |
| `0x5C` | `AEAD_MSG_LEN` | 8-bit Message / Ciphertext length (bytes) |
| `0x60` | `AEAD_STREAM_STATUS`| GIFT-COFB streaming/handshake status:<br>- `[4]` GIFT valid<br>- `[3]` GIFT done<br>- `[2]` GIFT AD request<br>- `[1]` GIFT Message request<br>- `[0]` GIFT data valid sticky |
| `0x64` | `AEAD_STREAM_CTRL` | GIFT-COFB streaming control:<br>- `[2]` Clear data valid sticky<br>- `[1]` AD ack pulse<br>- `[0]` Message ack pulse |
| `0x80` - `0x8C` | `AEAD_DOUT[0:3]` | 128-bit Output Data registers |
| `0x90` - `0x9C` | `AEAD_TAGOUT[0:3]`| 128-bit Output Tag registers |
| `0xA0` | `AEAD_MEAS_STATUS`| Performance measurement status (read-only) |
| `0xA4` | `AEAD_MEAS_CURR` | Current operation hardware cycle count |
| `0xA8` | `AEAD_MEAS_LAST` | Last operation hardware cycle count |
| `0xAC` | `AEAD_MEAS_TJ_LAST`| Last TinyJAMBU operation hardware cycle count |
| `0xB0` | `AEAD_MEAS_XD_LAST`| Last Xoodyak operation hardware cycle count |
| `0xB4` | `AEAD_MEAS_GF_LAST`| Last GIFT-COFB operation hardware cycle count |

### Algorithm Details

- **TinyJAMBU-128**:
  - Simple 128-bit Key, 96-bit Nonce, up to 16B AD, and up to 16B data processing per operation.
  - Done and Valid sticky flags are automatically managed and asserted upon completion.
- **Xoodyak (Optimized Keyed-Only)**:
  - All Hash-related state and logic were stripped to maximize ASIC area efficiency. Only the **Keyed AEAD** mode is supported.
  - Automatically runs and asserts `done` and `valid` flags in `AEAD_CTRL`.
- **GIFT-COFB**:
  - A block-cipher-based LWC algorithm supporting multi-block processing.
  - Employs an ACK/REQ handshake mechanism (via `AEAD_STREAM_STATUS` and `AEAD_STREAM_CTRL`) to stream additional AD and Message blocks dynamically within the permutation cycles.

---

## 4. Software Development Stack

### Firmware HAL Implementation

The system firmware provides a hardware abstraction layer (HAL) for the unified AEAD wrapper. Below is an example of performing a Xoodyak encryption:

```c
#define AEAD_BASE 0x30000000
#define AEAD_REG(off) (*(volatile uint32_t *)(AEAD_BASE + (off)))
#define AEAD_CTRL      AEAD_REG(0x00)
#define AEAD_KEY(i)    AEAD_REG(0x04 + (i) * 4)
#define AEAD_NONCE(i)  AEAD_REG(0x14 + (i) * 4)
#define AEAD_AD(i)     AEAD_REG(0x24 + (i) * 4)
#define AEAD_DIN(i)    AEAD_REG(0x34 + (i) * 4)
#define AEAD_DOUT(i)   AEAD_REG(0x80 + (i) * 4)
#define AEAD_TAGOUT(i) AEAD_REG(0x90 + (i) * 4)
#define AEAD_AD_LEN    AEAD_REG(0x54)
#define AEAD_DAT_LEN   AEAD_REG(0x58)

// 1. Load Key and Nonce
for (int i = 0; i < 4; i++) {
    AEAD_KEY(i) = key[i];
    AEAD_NONCE(i) = nonce[i];
}

// 2. Load Associated Data and Plaintext
AEAD_AD(0) = ad[0]; // etc.
AEAD_DIN(0) = pt[0]; // etc.
AEAD_AD_LEN = 9;   // 9 Bytes of AD
AEAD_DAT_LEN = 14; // 14 Bytes of Plaintext

// 3. Trigger Encryption (alg_sel = 1 for Xoodyak, start = 1, decrypt = 0)
AEAD_CTRL = (0u << 3) | (1u << 2) | 1u;

// 4. Wait for Done flag in AEAD_CTRL[6]
while (!(AEAD_CTRL & 0x40));

// 5. Read Ciphertext and Tag outputs
for (int i = 0; i < 4; i++) {
    ct[i] = AEAD_DOUT(i);
    tag[i] = AEAD_TAGOUT(i);
}
```

### Simulation Flow

Functional verification uses **Icarus Verilog** and **vvp**:

```bash
cd scripts/vivado/
make sim_system
```

This simulation command:
1. Compiles the RISC-V application firmware (`firmware.c`) using `riscv64-unknown-elf-gcc`.
2. Converts the compiled ELF binary to a `.hex` file.
3. Compiles the top-level SoC simulation target with all crypto cores using Icarus Verilog.
4. Executes the simulation with `vvp` to output functional status and performance metrics.

To build just the bare-metal application firmware:
```bash
cd firmware/
make firmware
```

---

## 5. ASIC Flow (OpenLane2)

The repository supports a complete digital backend physical design flow.

### Directory Structure

- `openlane/designs/picosoc/`: Design-specific configuration files.
- `openlane/designs/picosoc/src/`: Synchronized RTL source files.

### Synthesis and Physical Design Configuration

The configuration files under `openlane/` target the SkyWater 130nm process (`sky130`):

- **Clock**: Target 10ns (100 MHz).
- **Blackboxed Macros**: Core components like the 16 KB SRAM macro (`sky130_sram_4kbyte_1rw_32x1024_8`), the PicoRV32 AXI core (`picorv32_axi`), and the AEAD cluster (`crypto_cluster`) are handled as blackboxed macros.
- **Connectivity & IR Drop Overrides**: Due to blackboxed macros containing internal unconnected power routing, node connectivity checks and IR drop checks are bypassed in `config.json`:
  ```json
  "RUN_IR_DROP_REPORT": false,
  "FP_PDN_CHECK_NODES": false,
  "VSRC_LOC_FILES": ""
  ```
- **Re-running Flow**:
  ```bash
  cd openlane/
  python3 -m openlane.main --design designs/picosoc --flow
  ```

---

## 6. Files in the Repository

- `picorv32.v`: The base RISC-V core.
- `picosoc/`: SoC wrapper hardware modules, SPI master, and Crypto RTL cores.
- `firmware/`: Bootloader and application source files.
- `scripts/vivado/`: Standard simulation, testbench, and timing/utilization reports.
- `openlane/`: ASIC flow configurations and physical design outputs.
- `README.md`: This project documentation.

---

## 7. Credits and License

- **PicoRV32 / PicoSoC**: Claire Xenia Wolf (ISC License).
- **Crypto Accelerators**: Integrated, wrapped under a unified memory interface, and optimized for ASIC area efficiency.
