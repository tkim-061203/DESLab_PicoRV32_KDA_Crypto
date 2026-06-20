#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

summary_file="${ROOT_DIR}/report_timing_summary.txt"
tiny_file="${ROOT_DIR}/report_timing_tinyjambu.txt"
xoodoo_file="${ROOT_DIR}/report_timing_xoodyak.txt"
gift_file="${ROOT_DIR}/report_timing_giftcofb.txt"

extract_summary_wns() {
  awk '
    /WNS\(ns\)/ {capture=1; next}
    capture && $1 ~ /^-+$/ {next}
    capture && $1 ~ /^-?[0-9.]+$/ {print $1; exit}
  ' "$1"
}

extract_clock_period() {
  awk '$1 == "clk" && $2 ~ /^\{/ {print $4; exit}' "$1"
}

extract_clock_freq() {
  awk '$1 == "clk" && $2 ~ /^\{/ {print $5; exit}' "$1"
}

extract_path_wns() {
  awk '
    /^No timing paths found\./ {print "NA"; exit}
    /^Slack \(MET\)/ {val=$4; gsub("ns", "", val); print val; exit}
  ' "$1"
}

extract_requirement() {
  awk '
    /Requirement:/ {val=$2; gsub("ns", "", val); print val; exit}
  ' "$1"
}

print_fmax() {
  local name="$1"
  local period="$2"
  local wns="$3"
  awk -v n="$name" -v p="$period" -v w="$wns" '
    BEGIN {
      if (w == "NA" || p == "" || w == "") {
        printf "%-12s : unavailable\n", n;
      } else {
        eff = p - w;
        if (eff <= 0.0) {
          printf "%-12s : invalid (period=%s ns, wns=%s ns)\n", n, p, w;
        } else {
          fmax = 1000.0 / eff;
          printf "%-12s : period=%6.3f ns  WNS=%6.3f ns  est_fmax=%8.3f MHz\n", n, p, w, fmax;
        }
      }
    }
  '
}

if [[ ! -f "${summary_file}" ]]; then
  echo "Missing ${summary_file}. Run synth_system.tcl first."
  exit 1
fi

clk_period="$(extract_clock_period "${summary_file}")"
clk_freq="$(extract_clock_freq "${summary_file}")"
sys_wns="$(extract_summary_wns "${summary_file}")"

echo "Crypto Timing Summary"
echo "---------------------"
echo "Constraint clock : ${clk_period} ns (${clk_freq} MHz nominal)"
print_fmax "system" "${clk_period}" "${sys_wns}"

if [[ -f "${tiny_file}" ]]; then
  print_fmax "tinyjambu" "$(extract_requirement "${tiny_file}")" \
    "$(extract_path_wns "${tiny_file}")"
fi

if [[ -f "${xoodoo_file}" ]]; then
  print_fmax "xoodyak" "$(extract_requirement "${xoodoo_file}")" \
    "$(extract_path_wns "${xoodoo_file}")"
fi

if [[ -f "${gift_file}" ]]; then
  print_fmax "giftcofb" "$(extract_requirement "${gift_file}")" \
    "$(extract_path_wns "${gift_file}")"
fi
