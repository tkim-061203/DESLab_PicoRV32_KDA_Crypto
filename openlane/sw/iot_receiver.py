#!/usr/bin/env python3
"""
============================================================
IoT Gateway Receiver — PC-side UART packet parser
============================================================
Nhận packet mã hóa từ PicoSoC qua UART, parse và hiển thị.

Packet format:
  [PKT|<seq>|<algo>|<nonce_hex>|<ct_hex>|<tag_hex>|<crc8>]

Usage:
  python3 iot_receiver.py /dev/ttyUSB0 115200
  python3 iot_receiver.py COM3 115200
============================================================
"""

import sys
import serial
import time
from datetime import datetime


def crc8(data: bytes) -> int:
    """CRC-8 with polynomial 0x07 (matches firmware)."""
    crc = 0x00
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc


def parse_packet(line: str) -> dict:
    """Parse a [PKT|...] line into a dictionary."""
    line = line.strip()
    if not line.startswith("[PKT|") or not line.endswith("]"):
        return None

    inner = line[5:-1]  # Remove [PKT| and ]
    parts = inner.split("|")
    if len(parts) != 6:
        return None

    seq_str, algo, nonce_hex, ct_hex, tag_hex, crc_hex = parts

    # Verify CRC
    raw = bytes.fromhex(nonce_hex) + bytes.fromhex(ct_hex) + bytes.fromhex(tag_hex)
    expected_crc = crc8(raw)
    received_crc = int(crc_hex, 16)

    return {
        "seq": int(seq_str),
        "algo": algo,
        "nonce": nonce_hex,
        "ct": ct_hex,
        "tag": tag_hex,
        "crc_ok": expected_crc == received_crc,
        "crc_expected": f"{expected_crc:02x}",
        "crc_received": crc_hex,
        "raw_ct_bytes": bytes.fromhex(ct_hex),
        "raw_tag_bytes": bytes.fromhex(tag_hex),
        "timestamp": datetime.now().isoformat(),
    }


ALGO_NAMES = {
    "JB": "TinyJAMBU",
    "XD": "Xoodyak",
    "GC": "GIFT-COFB",
}


def print_packet(pkt: dict):
    """Pretty-print a parsed packet."""
    algo_name = ALGO_NAMES.get(pkt["algo"], pkt["algo"])
    crc_status = "✅" if pkt["crc_ok"] else f"❌ (expected {pkt['crc_expected']})"

    print(f"┌─── Encrypted Packet #{pkt['seq']} ───")
    print(f"│ Time:      {pkt['timestamp']}")
    print(f"│ Algorithm: {algo_name} [{pkt['algo']}]")
    print(f"│ Nonce:     {pkt['nonce']}")
    print(f"│ CT:        {pkt['ct']}")
    print(f"│ Tag:       {pkt['tag']}")
    print(f"│ CRC-8:     {pkt['crc_received']} {crc_status}")
    print(f"│ CT size:   {len(pkt['raw_ct_bytes'])} bytes")
    print(f"│ Tag size:  {len(pkt['raw_tag_bytes'])} bytes")
    print(f"└{'─' * 40}")
    print()


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 iot_receiver.py <port> [baudrate]")
        print("Example: python3 iot_receiver.py /dev/ttyUSB0 115200")
        sys.exit(1)

    port = sys.argv[1]
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

    print(f"╔══════════════════════════════════════════╗")
    print(f"║   PicoSoC IoT Gateway Receiver v1.0     ║")
    print(f"╠══════════════════════════════════════════╣")
    print(f"║ Port: {port:<34s} ║")
    print(f"║ Baud: {baud:<34d} ║")
    print(f"╚══════════════════════════════════════════╝")
    print()

    stats = {"total": 0, "jb": 0, "xd": 0, "gc": 0, "crc_fail": 0}

    try:
        ser = serial.Serial(port, baud, timeout=1)
        print(f"[*] Connected to {port}. Waiting for packets...\n")

        while True:
            line = ser.readline().decode("ascii", errors="replace").strip()
            if not line:
                continue

            # Print debug/comment lines from firmware
            if line.startswith("#"):
                print(f"  \033[90m{line}\033[0m")  # grey color
                continue

            # Parse packet lines
            pkt = parse_packet(line)
            if pkt:
                stats["total"] += 1
                stats[pkt["algo"].lower()] = stats.get(pkt["algo"].lower(), 0) + 1
                if not pkt["crc_ok"]:
                    stats["crc_fail"] += 1

                print_packet(pkt)

                # Print running stats every 10 packets
                if stats["total"] % 10 == 0:
                    print(f"  📊 Stats: {stats['total']} packets | "
                          f"JB:{stats.get('jb',0)} XD:{stats.get('xd',0)} "
                          f"GC:{stats.get('gc',0)} | "
                          f"CRC fail:{stats['crc_fail']}")
                    print()

    except serial.SerialException as e:
        print(f"[!] Serial error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print(f"\n[*] Stopped. Total packets received: {stats['total']}")
        print(f"    JB: {stats.get('jb',0)}  XD: {stats.get('xd',0)}  "
              f"GC: {stats.get('gc',0)}  CRC fail: {stats['crc_fail']}")


if __name__ == "__main__":
    main()
