#!/usr/bin/env python3
import sys
import os
import glob

# Default values (will be updated dynamically from the log)
FMAX_MHZ = {
    "TinyJAMBU": 100.000,
    "Xoodyak": 100.000,
    "GIFT-COFB": 100.000,
    "System-All": 100.000
}

def get_vivado_fmax(core_name):
    # Map core names to their Vivado timing report filenames
    name_map = {
        "TinyJAMBU": "tinyjambu",
        "Xoodyak": "xoodyak",
        "GIFT-COFB": "giftcofb"
    }
    if core_name not in name_map:
        return None
        
    report_path = os.path.join("..", "scripts", "vivado", f"report_timing_{name_map[core_name]}.txt")
    if not os.path.isfile(report_path):
        return None
        
    try:
        with open(report_path, 'r') as f:
            for line in f:
                if line.startswith("Slack") and "ns" in line:
                    slack_str = line.split(':')[1].split('ns')[0].strip()
                    slack = float(slack_str)
                    # Assuming 10ns (100MHz) clock period constraint
                    period = 10.000
                    fmax = 1000.0 / (period - slack)
                    return round(fmax, 3)
    except Exception:
        pass
    return None

def generate_report(log_file_path, output_rpt_path):
    if not os.path.isfile(log_file_path):
        print(f"Error: Could not find log file '{log_file_path}'")
        sys.exit(1)

    results_dict = {}

    # 1. First, try to auto-extract the REAL Fmax directly from Vivado timing reports!
    for core in ["TinyJAMBU", "Xoodyak", "GIFT-COFB"]:
        real_fmax = get_vivado_fmax(core)
        if real_fmax is not None:
            FMAX_MHZ[core] = real_fmax
            print(f"[*] Auto-detected {core} Fmax from Vivado report: {real_fmax} MHz")

    # Parse the log file, ignoring any binary garbage characters
    with open(log_file_path, 'r', errors='replace') as f:
        for line in f:
            # 1. Dynamically parse Fmax from the firmware's boot header
            if "#   est fmax tj" in line and "N/A" not in line:
                try: FMAX_MHZ["TinyJAMBU"] = float(line.split('=')[1].strip().split(' ')[0])
                except ValueError: pass
            elif "#   est fmax xoodyak" in line and "N/A" not in line:
                try: FMAX_MHZ["Xoodyak"] = float(line.split('=')[1].strip().split(' ')[0])
                except ValueError: pass
            elif "#   est fmax gift" in line and "N/A" not in line:
                try: FMAX_MHZ["GIFT-COFB"] = float(line.split('=')[1].strip().split(' ')[0])
                except ValueError: pass
            elif "#   nominal clk" in line and "N/A" not in line:
                try: FMAX_MHZ["System-All"] = float(line.split('=')[1].strip().split(' ')[0])
                except ValueError: pass

            # 2. Parse performance data
            elif line.startswith("PERF_DATA:"):
                # Example: PERF_DATA:TinyJAMBU,56,4,1500,2000
                parts = line.strip().split(':')[1].split(',')
                if len(parts) == 5:
                    name = parts[0]
                    payload_bytes = int(parts[1])
                    ops = int(parts[2])
                    core_cycles = int(parts[3])
                    total_cycles = int(parts[4])
                    results_dict[name] = (name, payload_bytes, ops, core_cycles, total_cycles)

    results = list(results_dict.values())

    if not results:
        print("Error: No 'PERF_DATA:' lines found in the log file.")
        sys.exit(1)

    # Generate the report
    with open(output_rpt_path, 'w') as out:
        out.write("========================================================\n")
        out.write("              HARDWARE THROUGHPUT REPORT                \n")
        out.write("========================================================\n\n")

        out.write(f"{'Core / Scope':<15} | {'Payload':<8} | {'Ops':<5} | {'Core Cyc':<10} | {'Total Cyc':<10} | {'HW Throughput':<15} | {'System Throughput':<15}\n")
        out.write("-" * 95 + "\n")

        for res in results:
            name, p_bytes, ops, core_cyc, total_cyc = res
            
            fmax = FMAX_MHZ.get(name, 100.0)

            # Core throughput applies only to individual cores, not system aggregate
            hw_throughput = "N/A"
            if name != "System-All" and core_cyc > 0:
                hw_mbps = (p_bytes * 8 * fmax) / core_cyc
                hw_throughput = f"{hw_mbps:.3f} Mbps"

            # System throughput applies to everything
            sys_throughput = "N/A"
            if total_cyc > 0:
                sys_mbps = (p_bytes * 8 * 100.0) / total_cyc
                sys_throughput = f"{sys_mbps:.3f} Mbps"

            out.write(f"{name:<15} | {p_bytes:<6} B | {ops:<5} | {core_cyc:<10} | {total_cyc:<10} | {hw_throughput:<15} | {sys_throughput:<15}\n")

        out.write("\n========================================================\n")
        out.write("Note: 'HW Throughput' assumes the core is running at its maximum frequency (Fmax).\n")
        out.write("      'System Throughput' assumes the entire SoC runs at the nominal 100 MHz clock.\n")

    print(f"Success! Report generated at: {output_rpt_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 generate_report.py <picocom_log.txt> <output_report.rpt>")
        sys.exit(1)
    
    generate_report(sys.argv[1], sys.argv[2])

