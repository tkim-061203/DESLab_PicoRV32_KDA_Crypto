#include <stdint.h>

#include <stddef.h>
void *memcpy(void *d, const void *s, size_t n) {
  uint8_t *dd = (uint8_t *)d;
  const uint8_t *ss = (const uint8_t *)s;
  while (n--)
    *dd++ = *ss++;
  return d;
}
void *memset(void *d, int c, size_t n) {
  uint8_t *dd = (uint8_t *)d;
  while (n--)
    *dd++ = (uint8_t)c;
  return d;
}

#define OUTBYTE (*(volatile uint32_t *)0x10000000)
#define UART_TX (*(volatile uint32_t *)0x10000004)
#define UART_ST (*(volatile uint32_t *)0x1000000C)

/* AEAD Unified Wrapper (base 0x3000_0000) */
#define AEAD_BASE 0x30000000
#define AEAD_REG(off) (*(volatile uint32_t *)(AEAD_BASE + (off)))

#define AEAD_CTRL      AEAD_REG(0x00)
#define AEAD_KEY(i)    AEAD_REG(0x04 + (i) * 4)
#define AEAD_NONCE(i)  AEAD_REG(0x14 + (i) * 4)
#define AEAD_AD(i)     AEAD_REG(0x24 + (i) * 4)
#define AEAD_DIN(i)    AEAD_REG(0x34 + (i) * 4)
#define AEAD_TAGIN(i)  AEAD_REG(0x44 + (i) * 4)

#define AEAD_AD_LEN    AEAD_REG(0x54)
#define AEAD_DAT_LEN   AEAD_REG(0x58)
#define AEAD_MSG_LEN   AEAD_REG(0x5C)

#define AEAD_DOUT(i)       AEAD_REG(0x80 + (i) * 4)
#define AEAD_TAGOUT(i)     AEAD_REG(0x90 + (i) * 4)
#define AEAD_STREAM_STATUS AEAD_REG(0x60)
#define AEAD_STREAM_CTRL   AEAD_REG(0x64)
#define AEAD_MEAS_STATUS   AEAD_REG(0xA0)
#define AEAD_MEAS_CURR     AEAD_REG(0xA4)
#define AEAD_MEAS_LAST     AEAD_REG(0xA8)
#define AEAD_MEAS_TJ_LAST  AEAD_REG(0xAC)
#define AEAD_MEAS_XD_LAST  AEAD_REG(0xB0)
#define AEAD_MEAS_GF_LAST  AEAD_REG(0xB4)

#define SOC_CLK_KHZ      100000u
#define SYS_EST_FMAX_KHZ 104877u
#define TJ_EST_FMAX_KHZ       0u
#define XD_EST_FMAX_KHZ  122459u
#define GF_EST_FMAX_KHZ  136110u

#define AEAD_ST_GIFT_DATA_VALID  0x01
#define AEAD_ST_GIFT_MSG_REQ     0x02
#define AEAD_ST_GIFT_AD_REQ      0x04
#define AEAD_ST_GIFT_DONE        0x08
#define AEAD_ST_GIFT_VALID       0x10

#define AEAD_CTRL_CLR_DATA_VALID 0x04
#define AEAD_CTRL_AD_ACK         0x02
#define AEAD_CTRL_MSG_ACK        0x01

#ifndef SKIP_SD_TEST
#define SKIP_SD_TEST 0
#endif

/* ---- UART ---- */
void pc(char c) {
  if (c == '\n') {
    while (!(UART_ST & 1))
      ;
    UART_TX = '\r';
  }
  while (!(UART_ST & 1))
    ;
  UART_TX = c;
}
void ps(const char *s) {
  while (*s)
    pc(*s++);
}
void ph(uint32_t v) {
  const char h[] = "0123456789abcdef";
  for (int i = 28; i >= 0; i -= 4)
    pc(h[(v >> i) & 0xF]);
}
void p128_inline(const uint32_t w[4]) {
  ph(w[3]);
  ph(w[2]);
  ph(w[1]);
  ph(w[0]);
}
void p128(const uint32_t w[4]) { p128_inline(w); }
void p96(const uint32_t w[3]) {
  ph(w[2]);
  ph(w[1]);
  ph(w[0]);
}
void p64(const uint32_t w[2]) {
  ph(w[1]);
  ph(w[0]);
}
void pd(uint32_t v) {
  char buf[10];
  int n = 0;
  if (!v) {
    pc('0');
    return;
  }
  while (v) {
    buf[n++] = '0' + (v % 10u);
    v /= 10u;
  }
  while (n--)
    pc(buf[n]);
}
void ln(void) { ps("# ----------------------------------------\n"); }

typedef struct {
  uint32_t ops;
  uint32_t payload_bytes;
  uint32_t core_cycles;
  uint32_t wait_cycles;
  uint32_t total_cycles;
} perf_stats_t;

static perf_stats_t perf_tinyjambu = {0};
static perf_stats_t perf_xoodyak   = {0};
static perf_stats_t perf_giftcofb  = {0};
static perf_stats_t perf_all       = {0};

static inline uint32_t rdcycle32(void) {
  uint32_t v;
  __asm__ volatile("rdcycle %0" : "=r"(v));
  return v;
}

static uint32_t aead_last_core_cycles(uint32_t alg_sel) {
  switch (alg_sel) {
  case 0u:
    return AEAD_MEAS_TJ_LAST;
  case 1u:
    return AEAD_MEAS_XD_LAST;
  default:
    return AEAD_MEAS_GF_LAST;
  }
}

static uint32_t aead_est_fmax_khz(uint32_t alg_sel) {
  switch (alg_sel) {
  case 0u:
    return TJ_EST_FMAX_KHZ;
  case 1u:
    return XD_EST_FMAX_KHZ;
  default:
    return GF_EST_FMAX_KHZ;
  }
}

static void print_mhz_x1000(uint32_t khz) {
  pd(khz / 1000u);
  pc('.');
  pc('0' + (char)((khz / 100u) % 10u));
  pc('0' + (char)((khz / 10u) % 10u));
  pc('0' + (char)(khz % 10u));
}

static void print_mbps_x1000(uint32_t milli_mbps) {
  pd(milli_mbps / 1000u);
  pc('.');
  pc('0' + (char)((milli_mbps / 100u) % 10u));
  pc('0' + (char)((milli_mbps / 10u) % 10u));
  pc('0' + (char)(milli_mbps % 10u));
}

static void print_metric_or_na(uint32_t value, int valid) {
  if (valid) {
    print_mbps_x1000(value);
  } else {
    ps("N/A");
  }
}

static uint32_t calc_mbps_x1000(uint32_t payload_bytes, uint32_t cycles,
                                 uint32_t freq_khz) {
  uint64_t payload_bits = (uint64_t)payload_bytes * 8u;
  if (!cycles)
    return 0u;
  return (uint32_t)((payload_bits * freq_khz) / cycles);
}

static void perf_update(perf_stats_t *stats, uint32_t payload_bytes,
                        uint32_t core_cycles, uint32_t wait_cycles,
                        uint32_t total_cycles) {
  stats->ops           += 1u;
  stats->payload_bytes += payload_bytes;
  stats->core_cycles   += core_cycles;
  stats->wait_cycles   += wait_cycles;
  stats->total_cycles  += total_cycles;
  perf_all.ops           += 1u;
  perf_all.payload_bytes += payload_bytes;
  perf_all.core_cycles   += core_cycles;
  perf_all.wait_cycles   += wait_cycles;
  perf_all.total_cycles  += total_cycles;
}

static void perf_print_one(const char *name, const char *phase,
                           uint32_t payload_bytes, uint32_t core_cycles,
                           uint32_t wait_cycles, uint32_t total_cycles,
                           uint32_t core_fmax_khz) {
  (void)name;
  (void)phase;
  (void)payload_bytes;
  (void)core_cycles;
  (void)wait_cycles;
  (void)total_cycles;
  (void)core_fmax_khz;
}

static void perf_print_summary(const char *name, const perf_stats_t *stats,
                               uint32_t core_fmax_khz) {
  (void)core_fmax_khz;
  ps("PERF_DATA:");
  ps(name);
  ps(",");
  pd(stats->payload_bytes);
  ps(",");
  pd(stats->ops);
  ps(",");
  pd(stats->core_cycles);
  ps(",");
  pd(stats->total_cycles);
  ps("\n");
}

static void aead_read_data_block(uint32_t w[4]) {
  w[0] = AEAD_DOUT(0);
  w[1] = AEAD_DOUT(1);
  w[2] = AEAD_DOUT(2);
  w[3] = AEAD_DOUT(3);
}

static void aead_read_tag_block(uint32_t w[4]) {
  w[0] = AEAD_TAGOUT(0);
  w[1] = AEAD_TAGOUT(1);
  w[2] = AEAD_TAGOUT(2);
  w[3] = AEAD_TAGOUT(3);
}

static int eq128(const uint32_t a[4], const uint32_t b[4]) {
  return (a[0] == b[0]) && (a[1] == b[1]) && (a[2] == b[2]) && (a[3] == b[3]);
}

static int eq128_masked(const uint32_t a[4], const uint32_t b[4],
                        uint32_t word0_mask) {
  return ((a[0] & word0_mask) == (b[0] & word0_mask)) && (a[1] == b[1]) &&
         (a[2] == b[2]) && (a[3] == b[3]);
}

static void aead_clear_data_valid(void) {
  AEAD_STREAM_CTRL = AEAD_CTRL_CLR_DATA_VALID;
}

static void aead_gift_ack_ad(void) { AEAD_STREAM_CTRL = AEAD_CTRL_AD_ACK; }

static void aead_gift_ack_msg(void) { AEAD_STREAM_CTRL = AEAD_CTRL_MSG_ACK; }

/* ====================================================
 * CORE 1: TinyJAMBU-128 AEAD
 *
 * Array convention (same as rest of file):
 *   uint32_t w[4]: w[0]=LSW (Verilog[31:0]),  w[3]=MSW (Verilog[127:96])
 *   128-bit fields left-aligned: valid bytes at MSW side, zeros at LSW.
 *   96-bit nonce:  w[0]=nonce[31:0],  w[2]=nonce[95:64]
 *   64-bit tag:    w[0]=tag[31:0],    w[1]=tag[63:32]
 * ==================================================== */

/* Helper: run one TinyJAMBU encrypt+decrypt test case, return 1 if both pass */
static int jb_test(const char *label, const uint32_t key[4],
                   const uint32_t nonce[3], const uint32_t ad[4],
                   uint32_t adlen, const uint32_t pt[4],
                   const uint32_t exp_ct[4], uint32_t mlen,
                   const uint32_t exp_tag[2]) {
  uint32_t ct[4] = {0u, 0u, 0u, 0u};
  uint32_t tag[2] = {0u, 0u};
  uint32_t dec[4] = {0u, 0u, 0u, 0u};
  uint32_t op_begin, wait_begin;
  uint32_t enc_wait_cycles, enc_total_cycles, enc_core_cycles;
  uint32_t dec_wait_cycles, dec_total_cycles, dec_core_cycles;
  int valid;

  ps(label);
  pc('\n');
  ps("Input:\n");
  ps("Key          : ");
  p128(key);
  pc('\n');
  ps("Nonce        : ");
  p96(nonce);
  pc('\n');
  ps("AD           : ");
  p128(ad);
  pc('\n');
  ps("Plaintext    : ");
  p128(pt);
  pc('\n');
  ps("Output (Encrypt):\n");

  /* Encrypt */
  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_AD(0) = ad[0];
  AEAD_AD(1) = ad[1];
  AEAD_AD(2) = ad[2];
  AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = pt[0];
  AEAD_DIN(1) = pt[1];
  AEAD_DIN(2) = pt[2];
  AEAD_DIN(3) = pt[3];
  AEAD_AD_LEN  = adlen;
  AEAD_DAT_LEN = mlen;
  wait_begin = rdcycle32();
  AEAD_CTRL = (0u << 3) | (1u << 2) | 0u; /* encrypt, start, sel=TinyJAMBU */
  while (!(AEAD_CTRL & 0x40))
    ;
  enc_wait_cycles = rdcycle32() - wait_begin;

  ct[0] = AEAD_DOUT(0);
  ct[1] = AEAD_DOUT(1);
  ct[2] = AEAD_DOUT(2);
  ct[3] = AEAD_DOUT(3);
  tag[0] = AEAD_TAGOUT(0);
  tag[1] = AEAD_TAGOUT(1);
  enc_total_cycles = rdcycle32() - op_begin;
  enc_core_cycles  = aead_last_core_cycles(0u);

  int enc_ok = eq128(ct, exp_ct) &&
               (tag[0] == exp_tag[0]) && (tag[1] == exp_tag[1]);

  ps("Ciphertext   : ");
  p128(ct);
  pc('\n');
  ps("Tag          : ");
  p64(tag);
  pc('\n');
  ps("ENCRYPT      : ");
  ps(enc_ok ? "PASS\n" : "FAIL\n");

  perf_print_one("TinyJAMBU", "encrypt", mlen, enc_core_cycles,
                 enc_wait_cycles, enc_total_cycles, aead_est_fmax_khz(0u));
  perf_update(&perf_tinyjambu, mlen, enc_core_cycles,
              enc_wait_cycles, enc_total_cycles);

  /* Decrypt */
  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_AD(0) = ad[0];
  AEAD_AD(1) = ad[1];
  AEAD_AD(2) = ad[2];
  AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = ct[0];
  AEAD_DIN(1) = ct[1];
  AEAD_DIN(2) = ct[2];
  AEAD_DIN(3) = ct[3];
  AEAD_TAGIN(0) = tag[0];
  AEAD_TAGIN(1) = tag[1];
  AEAD_AD_LEN  = adlen;
  AEAD_DAT_LEN = mlen;
  wait_begin = rdcycle32();
  AEAD_CTRL = (1u << 3) | (1u << 2) | 0u; /* decrypt, start, sel=TinyJAMBU */
  while (!(AEAD_CTRL & 0x40))
    ;
  dec_wait_cycles = rdcycle32() - wait_begin;

  dec[0] = AEAD_DOUT(0);
  dec[1] = AEAD_DOUT(1);
  dec[2] = AEAD_DOUT(2);
  dec[3] = AEAD_DOUT(3);
  valid = (AEAD_CTRL & 0x80) ? 1 : 0;
  dec_total_cycles = rdcycle32() - op_begin;
  dec_core_cycles  = aead_last_core_cycles(0u);

  int dec_ok = valid && eq128(dec, pt);

  ps("Output (Decrypt):\n");
  ps("Decrypted    : ");
  p128(dec);
  pc('\n');
  ps("Valid        : ");
  pc(valid ? '1' : '0');
  pc('\n');
  ps("DECRYPT      : ");
  ps(dec_ok ? "PASS\n" : "FAIL\n");

  perf_print_one("TinyJAMBU", "decrypt", mlen, dec_core_cycles,
                 dec_wait_cycles, dec_total_cycles, aead_est_fmax_khz(0u));
  perf_update(&perf_tinyjambu, mlen, dec_core_cycles,
              dec_wait_cycles, dec_total_cycles);

  return enc_ok && dec_ok;
}

void test_tinyjambu(int *pass) {
  int ok1, ok2;

  ps("========================================\n");
  ps("[CORE 1] TinyJAMBU-128 AEAD\n");
  ps("========================================\n");

  /* TC1: NIST LWC Msg 9 (AD=12B, MSG=12B)
   * key  = 899CD0F7C88A9CDD405D3CCD628D2DDB
   * npub = 535E438A89158AF8D7F6659B
   * ad   = 49A44D0EF0AC0C0EF1C0D2B4
   * pt   = 3BF1A7D289F0E4353CDB944B
   * ct   = 73C2C23AF3BEB3F2F04D0F20
   * tag  = E0D0722E1DEC6827                  */
  uint32_t key1[4]  = {0x628D2DDB, 0x405D3CCD, 0xC88A9CDD, 0x899CD0F7};
  uint32_t nonce1[3]= {0xD7F6659B, 0x89158AF8, 0x535E438A};
  uint32_t ad1[4]   = {0x00000000, 0xF1C0D2B4, 0xF0AC0C0E, 0x49A44D0E};
  uint32_t pt1[4]   = {0x00000000, 0x3CDB944B, 0x89F0E435, 0x3BF1A7D2};
  uint32_t ect1[4]  = {0x00000000, 0xF04D0F20, 0xF3BEB3F2, 0x73C2C23A};
  uint32_t etag1[2] = {0x1DEC6827, 0xE0D0722E};
  ok1 = jb_test("Test Vector 1: AD=12B, MSG=12B",
                key1, nonce1, ad1, 12, pt1, ect1, 12, etag1);

  /* TC2: NIST LWC Msg 10 (AD=16B, MSG=16B)
   * key  = 2BBF8981A0BF5446B8B647DD6B9DF1B7
   * npub = 62AB30BEF8B84C8E47B2FA5D
   * ad   = F37A89F695D38CE06549FACD150BBA1E
   * pt   = 40C8D8F22A73580E14AB5FE6C8325FEC
   * ct   = 3730C94A3A77204B55E3D4F33EBD5A89
   * tag  = FA0FE4E76EBDAFD0                  */
  uint32_t key2[4]  = {0x6B9DF1B7, 0xB8B647DD, 0xA0BF5446, 0x2BBF8981};
  uint32_t nonce2[3]= {0x47B2FA5D, 0xF8B84C8E, 0x62AB30BE};
  uint32_t ad2[4]   = {0x150BBA1E, 0x6549FACD, 0x95D38CE0, 0xF37A89F6};
  uint32_t pt2[4]   = {0xC8325FEC, 0x14AB5FE6, 0x2A73580E, 0x40C8D8F2};
  uint32_t ect2[4]  = {0x3EBD5A89, 0x55E3D4F3, 0x3A77204B, 0x3730C94A};
  uint32_t etag2[2] = {0x6EBDAFD0, 0xFA0FE4E7};
  ok2 = jb_test("Test Vector 2: AD=16B, MSG=16B",
                key2, nonce2, ad2, 16, pt2, ect2, 16, etag2);

  ps("----------------------------------------\n");
  ps((ok1 && ok2) ? "TinyJAMBU : 2/2 PASSED\n\n"
                  : "TinyJAMBU : SOME TESTS FAILED\n\n");
  *pass = ok1 && ok2;
}

/* ====================================================
 * CORE 2: Xoodyak (Custom - 9B AD, 14B PT, KAT verified)
 * ==================================================== */
void test_xoodyak(int *pass) {
  uint32_t key[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  uint32_t nonce[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  uint32_t ad[4] = {0x00000000, 0x08000000, 0x04050607, 0x00010203};
  uint32_t pt[4] = {0x0c0d0e00, 0x08090a0b, 0x04050607, 0x00010203};
  uint32_t exp_ct1[4] = {0x93090000, 0x6b339d70, 0x24fb2cc1, 0x76e90670};
  uint32_t exp_tag1[4] = {0xBF7B3E0B, 0x5607B323, 0x7579E7C0, 0xBD9C91A7};
  uint32_t ct[4], tag[4], dec[4];
  uint32_t op_begin, wait_begin;
  uint32_t enc_wait_cycles, enc_total_cycles, enc_core_cycles;
  uint32_t dec_wait_cycles, dec_total_cycles, dec_core_cycles;
  int v1_ok = 0, v2_ok = 0;

  ps("========================================\n");
  ps("[CORE 2] Xoodyak AEAD\n");
  ps("========================================\n");
  ps("Test Vector 1: AD=9B, MSG=14B\n");
  ps("Input:\n");
  ps("Key          : ");
  p128(key);
  pc('\n');
  ps("Nonce        : ");
  p128(nonce);
  pc('\n');
  ps("AD           : ");
  p128(ad);
  pc('\n');
  ps("Plaintext    : ");
  p128(pt);
  pc('\n');
  ps("Output (Encrypt):\n");

  /* Encrypt */
  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad[0];
  AEAD_AD(1) = ad[1];
  AEAD_AD(2) = ad[2];
  AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = pt[0];
  AEAD_DIN(1) = pt[1];
  AEAD_DIN(2) = pt[2];
  AEAD_DIN(3) = pt[3];
  AEAD_AD_LEN = 9u;
  AEAD_DAT_LEN = 14u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (0u << 3) | (1u << 2) | 1u;
  while (!(AEAD_CTRL & 0x40))
    ;
  enc_wait_cycles = rdcycle32() - wait_begin;

  ct[0] = AEAD_DOUT(0);
  ct[1] = AEAD_DOUT(1);
  ct[2] = AEAD_DOUT(2);
  ct[3] = AEAD_DOUT(3);
  tag[0] = AEAD_TAGOUT(0);
  tag[1] = AEAD_TAGOUT(1);
  tag[2] = AEAD_TAGOUT(2);
  tag[3] = AEAD_TAGOUT(3);
  enc_total_cycles = rdcycle32() - op_begin;
  enc_core_cycles = aead_last_core_cycles(1u);

  ps("Ciphertext   : ");
  p128(ct);
  pc('\n');
  ps("Tag          : ");
  p128(tag);
  pc('\n');
  {
    int ct_ok = eq128_masked(ct, exp_ct1, 0xFFFF0000);
    int tag_ok = eq128(tag, exp_tag1);
    ps("ENCRYPT      : ");
    ps((ct_ok && tag_ok) ? "PASS\n" : "FAIL\n");
    v1_ok = ct_ok && tag_ok;
  }
  perf_print_one("Xoodyak", "encrypt_14B", 14u, enc_core_cycles,
                 enc_wait_cycles, enc_total_cycles, aead_est_fmax_khz(1u));
  perf_update(&perf_xoodyak, 14u, enc_core_cycles, enc_wait_cycles,
              enc_total_cycles);
  ps("Output (Decrypt):\n");

  /* Decrypt */
  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad[0];
  AEAD_AD(1) = ad[1];
  AEAD_AD(2) = ad[2];
  AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = ct[0];
  AEAD_DIN(1) = ct[1];
  AEAD_DIN(2) = ct[2];
  AEAD_DIN(3) = ct[3];
  AEAD_TAGIN(0) = tag[0];
  AEAD_TAGIN(1) = tag[1];
  AEAD_TAGIN(2) = tag[2];
  AEAD_TAGIN(3) = tag[3];
  AEAD_AD_LEN = 9u;
  AEAD_DAT_LEN = 14u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (1u << 3) | (1u << 2) | 1u;
  while (!(AEAD_CTRL & 0x40))
    ;
  dec_wait_cycles = rdcycle32() - wait_begin;

  dec[0] = AEAD_DOUT(0);
  dec[1] = AEAD_DOUT(1);
  dec[2] = AEAD_DOUT(2);
  dec[3] = AEAD_DOUT(3);
  dec_total_cycles = rdcycle32() - op_begin;
  dec_core_cycles = aead_last_core_cycles(1u);
  ps("Decrypted    : ");
  p128(dec);
  pc('\n');
  ps("Valid        : ");
  pc((AEAD_CTRL & 0x80) ? '1' : '0');
  pc('\n');
  v1_ok = v1_ok && ((AEAD_CTRL & 0x80) && eq128_masked(dec, pt, 0xFFFF0000));
  ps("DECRYPT      : ");
  ps(v1_ok ? "PASS\n\n" : "FAIL\n\n");
  perf_print_one("Xoodyak", "decrypt_14B", 14u, dec_core_cycles,
                 dec_wait_cycles, dec_total_cycles, aead_est_fmax_khz(1u));
  perf_update(&perf_xoodyak, 14u, dec_core_cycles, dec_wait_cycles,
              dec_total_cycles);

  {
    uint32_t key2[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t nonce2[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t ad2[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t pt2[4] = {0x1c1d1e1f, 0x18191a1b, 0x14151617, 0x10111213};
    uint32_t exp_ct2[4] = {0x6689f444, 0x4de1ecb0, 0xc41782e2, 0x49c849d1};
    uint32_t exp_tag2[4] = {0x80bdf15f, 0x7f1c545d, 0x7590c7a8, 0xe071d23a};

    ps("Test Vector 2: AD=16B, MSG=16B\n");
    ps("Input:\n");
    ps("Key          : ");
    p128(key2);
    pc('\n');
    ps("Nonce        : ");
    p128(nonce2);
    pc('\n');
    ps("AD           : ");
    p128(ad2);
    pc('\n');
    ps("Plaintext    : ");
    p128(pt2);
    pc('\n');
    ps("Output (Encrypt):\n");

    op_begin = rdcycle32();
    AEAD_KEY(0) = key2[0];
    AEAD_KEY(1) = key2[1];
    AEAD_KEY(2) = key2[2];
    AEAD_KEY(3) = key2[3];
    AEAD_NONCE(0) = nonce2[0];
    AEAD_NONCE(1) = nonce2[1];
    AEAD_NONCE(2) = nonce2[2];
    AEAD_NONCE(3) = nonce2[3];
    AEAD_AD(0) = ad2[0];
    AEAD_AD(1) = ad2[1];
    AEAD_AD(2) = ad2[2];
    AEAD_AD(3) = ad2[3];
    AEAD_DIN(0) = pt2[0];
    AEAD_DIN(1) = pt2[1];
    AEAD_DIN(2) = pt2[2];
    AEAD_DIN(3) = pt2[3];
    AEAD_AD_LEN = 16u;
    AEAD_DAT_LEN = 16u;
    wait_begin = rdcycle32();
    AEAD_CTRL = (0u << 3) | (1u << 2) | 1u;
    while (!(AEAD_CTRL & 0x40))
      ;
    enc_wait_cycles = rdcycle32() - wait_begin;

    aead_read_data_block(ct);
    aead_read_tag_block(tag);
    enc_total_cycles = rdcycle32() - op_begin;
    enc_core_cycles = aead_last_core_cycles(1u);

    ps("Ciphertext   : ");
    p128(ct);
    pc('\n');
    ps("Tag          : ");
    p128(tag);
    pc('\n');
    v2_ok = eq128(ct, exp_ct2) && eq128(tag, exp_tag2);
    ps("ENCRYPT      : ");
    ps(v2_ok ? "PASS\n" : "FAIL\n");
    perf_print_one("Xoodyak", "encrypt_16B", 16u, enc_core_cycles,
                   enc_wait_cycles, enc_total_cycles, aead_est_fmax_khz(1u));
    perf_update(&perf_xoodyak, 16u, enc_core_cycles, enc_wait_cycles,
                enc_total_cycles);
    ps("Output (Decrypt):\n");

    op_begin = rdcycle32();
    AEAD_KEY(0) = key2[0];
    AEAD_KEY(1) = key2[1];
    AEAD_KEY(2) = key2[2];
    AEAD_KEY(3) = key2[3];
    AEAD_NONCE(0) = nonce2[0];
    AEAD_NONCE(1) = nonce2[1];
    AEAD_NONCE(2) = nonce2[2];
    AEAD_NONCE(3) = nonce2[3];
    AEAD_AD(0) = ad2[0];
    AEAD_AD(1) = ad2[1];
    AEAD_AD(2) = ad2[2];
    AEAD_AD(3) = ad2[3];
    AEAD_DIN(0) = ct[0];
    AEAD_DIN(1) = ct[1];
    AEAD_DIN(2) = ct[2];
    AEAD_DIN(3) = ct[3];
    AEAD_TAGIN(0) = tag[0];
    AEAD_TAGIN(1) = tag[1];
    AEAD_TAGIN(2) = tag[2];
    AEAD_TAGIN(3) = tag[3];
    AEAD_AD_LEN = 16u;
    AEAD_DAT_LEN = 16u;
    wait_begin = rdcycle32();
    AEAD_CTRL = (1u << 3) | (1u << 2) | 1u;
    while (!(AEAD_CTRL & 0x40))
      ;
    dec_wait_cycles = rdcycle32() - wait_begin;

    aead_read_data_block(dec);
    dec_total_cycles = rdcycle32() - op_begin;
    dec_core_cycles = aead_last_core_cycles(1u);
    ps("Decrypted    : ");
    p128(dec);
    pc('\n');
    ps("Valid        : ");
    pc((AEAD_CTRL & 0x80) ? '1' : '0');
    pc('\n');
    v2_ok = v2_ok && ((AEAD_CTRL & 0x80) && eq128(dec, pt2));
    ps("VERIFY       : ");
    ps(v2_ok ? "PASS\n" : "FAIL\n");
    perf_print_one("Xoodyak", "decrypt_16B", 16u, dec_core_cycles,
                   dec_wait_cycles, dec_total_cycles, aead_est_fmax_khz(1u));
    perf_update(&perf_xoodyak, 16u, dec_core_cycles, dec_wait_cycles,
                dec_total_cycles);
  }
  ps("----------------------------------------\n");
  ps((v1_ok && v2_ok) ? "Xoodyak   : 2/2 PASSED\n\n"
                      : "Xoodyak   : SOME TESTS FAILED\n\n");

  *pass = v1_ok && v2_ok;
}

/* ====================================================
 * CORE 3: GIFT-COFB
 *
 * Test A: Single-block (KAT #533)
 *   AD=4B, PT=16B
 *
 * Test B: Multi-block (KAT #579)
 *   AD=17B (2 blocks), PT=17B (2 blocks)
 *   Exercises req/ack handshaking
 *
 * STATUS register: [3]=ad_req [2]=msg_req [1]=done [0]=valid
 * ACK register (0x78): [1]=ad_ack [0]=msg_ack
 * ==================================================== */

void test_giftcofb(int *pass) {
  uint32_t op_begin, wait_begin;
  uint32_t run_wait_cycles, run_total_cycles, run_core_cycles;
  uint32_t status;
  int all_ok = 1;

  const uint32_t key[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  const uint32_t nonce[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};

  const uint32_t ad4[4] = {0x00000000, 0x00000000, 0x00000000, 0x00010203};
  const uint32_t pt16[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  const uint32_t ct16_exp[4] = {0xff6cc70d, 0xe2ad9211, 0xf3ceaebb, 0xaca0e4da};
  const uint32_t tag16_exp[4] = {0x7490194c, 0x0cc8bae6, 0xbbbd8b17,
                                 0x51859c4e};

  const uint32_t blk0_16[4] = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
  const uint32_t blk1_1b[4] = {0x00000000, 0x00000000, 0x00000000, 0x10000000};
  const uint32_t ct_blk0_exp[4] = {0xda23161c, 0x824effe3, 0xb7680d22,
                                   0x54b63042};
  const uint32_t ct_blk1_exp[4] = {0x00000000, 0x00000000, 0x00000000,
                                   0x2d000000};
  const uint32_t tag17_exp[4] = {0x9c079228, 0xa0da3055, 0xb0433543,
                                 0x82c5c511};

  uint32_t out0[4], out1[4], tag[4], dec0[4], dec1[4];
  int got_out0, got_out1, ad_sent, msg_sent;

  ps("========================================\n");
  ps("[CORE 3] GIFT-COFB AEAD\n");
  ps("========================================\n");
  ps("Test Vector 1: Single-block (KAT #533, AD=4B, PT=16B)\n");
  ps("Input:\n");
  ps("Key          : ");
  p128(key);
  pc('\n');
  ps("Nonce        : ");
  p128(nonce);
  pc('\n');
  ps("AD (4B)      : ");
  p128(ad4);
  pc('\n');
  ps("Plaintext    : ");
  p128(pt16);
  pc('\n');
  ps("Output (Encrypt):\n");

  /* Encrypt */
  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad4[0];
  AEAD_AD(1) = ad4[1];
  AEAD_AD(2) = ad4[2];
  AEAD_AD(3) = ad4[3];
  AEAD_DIN(0) = pt16[0];
  AEAD_DIN(1) = pt16[1];
  AEAD_DIN(2) = pt16[2];
  AEAD_DIN(3) = pt16[3];
  AEAD_AD_LEN = 4u;
  AEAD_MSG_LEN = 16u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (0u << 3) | (1u << 2) | 2u;
  while (!(AEAD_CTRL & 0x40))
    ;
  run_wait_cycles = rdcycle32() - wait_begin;

  aead_read_data_block(out0);
  aead_read_tag_block(tag);
  run_total_cycles = rdcycle32() - op_begin;
  run_core_cycles = aead_last_core_cycles(2u);

  ps("Ciphertext   : ");
  p128(out0);
  pc('\n');
  ps("Tag          : ");
  p128(tag);
  pc('\n');
  ps("ENCRYPT      : ");
  if (eq128(out0, ct16_exp) && eq128(tag, tag16_exp)) {
    ps("PASS\n");
  } else {
    ps("FAIL\n");
    all_ok = 0;
  }
  perf_print_one("GIFT-COFB", "encrypt_16B", 16u, run_core_cycles,
                 run_wait_cycles, run_total_cycles, aead_est_fmax_khz(2u));
  perf_update(&perf_giftcofb, 16u, run_core_cycles, run_wait_cycles,
              run_total_cycles);

  ps("Output (Decrypt):\n");

  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad4[0];
  AEAD_AD(1) = ad4[1];
  AEAD_AD(2) = ad4[2];
  AEAD_AD(3) = ad4[3];
  AEAD_DIN(0) = ct16_exp[0];
  AEAD_DIN(1) = ct16_exp[1];
  AEAD_DIN(2) = ct16_exp[2];
  AEAD_DIN(3) = ct16_exp[3];
  AEAD_TAGIN(0) = tag16_exp[0];
  AEAD_TAGIN(1) = tag16_exp[1];
  AEAD_TAGIN(2) = tag16_exp[2];
  AEAD_TAGIN(3) = tag16_exp[3];
  AEAD_AD_LEN = 4u;
  AEAD_MSG_LEN = 16u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (1u << 3) | (1u << 2) | 2u;
  while (!(AEAD_CTRL & 0x40))
    ;
  run_wait_cycles = rdcycle32() - wait_begin;

  aead_read_data_block(dec0);
  run_total_cycles = rdcycle32() - op_begin;
  run_core_cycles = aead_last_core_cycles(2u);
  ps("Decrypted    : ");
  p128(dec0);
  pc('\n');
  ps("Valid        : ");
  pc((AEAD_CTRL & 0x80) ? '1' : '0');
  pc('\n');
  ps("DECRYPT      : ");
  if ((AEAD_CTRL & 0x80) && eq128(dec0, pt16)) {
    ps("PASS\n\n");
  } else {
    ps("FAIL\n\n");
    all_ok = 0;
  }
  perf_print_one("GIFT-COFB", "decrypt_16B", 16u, run_core_cycles,
                 run_wait_cycles, run_total_cycles, aead_est_fmax_khz(2u));
  perf_update(&perf_giftcofb, 16u, run_core_cycles, run_wait_cycles,
              run_total_cycles);

  ps("Test Vector 2: Multi-block (KAT #579, AD=17B, PT=17B)\n");
  ps("Input:\n");
  ps("Key          : ");
  p128(key);
  pc('\n');
  ps("Nonce        : ");
  p128(nonce);
  pc('\n');
  ps("AD (17B)     : ");
  p128(blk0_16);
  ph(blk1_1b[3]);
  pc('\n');
  ps("MSG (17B)    : ");
  p128(blk0_16);
  ph(blk1_1b[3]);
  pc('\n');
  ps("Output (Encrypt):\n");

  got_out0 = 0;
  got_out1 = 0;
  ad_sent = 0;
  msg_sent = 0;
  aead_clear_data_valid();

  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = blk0_16[0];
  AEAD_AD(1) = blk0_16[1];
  AEAD_AD(2) = blk0_16[2];
  AEAD_AD(3) = blk0_16[3];
  AEAD_DIN(0) = blk0_16[0];
  AEAD_DIN(1) = blk0_16[1];
  AEAD_DIN(2) = blk0_16[2];
  AEAD_DIN(3) = blk0_16[3];
  AEAD_AD_LEN = 17u;
  AEAD_MSG_LEN = 17u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (0u << 3) | (1u << 2) | 2u;
  while (!(AEAD_CTRL & 0x40)) {
    status = AEAD_STREAM_STATUS;
    if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out0) {
      aead_read_data_block(out0);
      got_out0 = 1;
      aead_clear_data_valid();
    } else if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out1) {
      aead_read_data_block(out1);
      got_out1 = 1;
      aead_clear_data_valid();
    }
    if ((status & AEAD_ST_GIFT_AD_REQ) && !ad_sent) {
      AEAD_AD(0) = blk1_1b[0];
      AEAD_AD(1) = blk1_1b[1];
      AEAD_AD(2) = blk1_1b[2];
      AEAD_AD(3) = blk1_1b[3];
      aead_gift_ack_ad();
      ad_sent = 1;
    }
    if ((status & AEAD_ST_GIFT_MSG_REQ) && !msg_sent) {
      AEAD_DIN(0) = blk1_1b[0];
      AEAD_DIN(1) = blk1_1b[1];
      AEAD_DIN(2) = blk1_1b[2];
      AEAD_DIN(3) = blk1_1b[3];
      aead_gift_ack_msg();
      msg_sent = 1;
    }
  }
  run_wait_cycles = rdcycle32() - wait_begin;
  status = AEAD_STREAM_STATUS;
  if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out1) {
    aead_read_data_block(out1);
    got_out1 = 1;
    aead_clear_data_valid();
  }
  aead_read_tag_block(tag);
  run_total_cycles = rdcycle32() - op_begin;
  run_core_cycles = aead_last_core_cycles(2u);

  ps("CT blk0      : ");
  p128(out0);
  pc('\n');
  ps("CT blk1      : ");
  ph(out1[3]);
  pc('\n');
  ps("Tag          : ");
  p128(tag);
  pc('\n');
  ps("ENCRYPT      : ");
  if (got_out0 && got_out1 && eq128(out0, ct_blk0_exp) &&
      eq128(out1, ct_blk1_exp) && eq128(tag, tag17_exp)) {
    ps("PASS\n");
  } else {
    ps("FAIL\n");
    all_ok = 0;
  }
  perf_print_one("GIFT-COFB", "encrypt_17B", 17u, run_core_cycles,
                 run_wait_cycles, run_total_cycles, aead_est_fmax_khz(2u));
  perf_update(&perf_giftcofb, 17u, run_core_cycles, run_wait_cycles,
              run_total_cycles);

  ps("Output (Decrypt):\n");

  got_out0 = 0;
  got_out1 = 0;
  ad_sent = 0;
  msg_sent = 0;
  aead_clear_data_valid();

  op_begin = rdcycle32();
  AEAD_KEY(0) = key[0];
  AEAD_KEY(1) = key[1];
  AEAD_KEY(2) = key[2];
  AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0];
  AEAD_NONCE(1) = nonce[1];
  AEAD_NONCE(2) = nonce[2];
  AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = blk0_16[0];
  AEAD_AD(1) = blk0_16[1];
  AEAD_AD(2) = blk0_16[2];
  AEAD_AD(3) = blk0_16[3];
  AEAD_DIN(0) = ct_blk0_exp[0];
  AEAD_DIN(1) = ct_blk0_exp[1];
  AEAD_DIN(2) = ct_blk0_exp[2];
  AEAD_DIN(3) = ct_blk0_exp[3];
  AEAD_TAGIN(0) = tag17_exp[0];
  AEAD_TAGIN(1) = tag17_exp[1];
  AEAD_TAGIN(2) = tag17_exp[2];
  AEAD_TAGIN(3) = tag17_exp[3];
  AEAD_AD_LEN = 17u;
  AEAD_MSG_LEN = 17u;
  wait_begin = rdcycle32();
  AEAD_CTRL = (1u << 3) | (1u << 2) | 2u;
  while (!(AEAD_CTRL & 0x40)) {
    status = AEAD_STREAM_STATUS;
    if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out0) {
      aead_read_data_block(dec0);
      got_out0 = 1;
      aead_clear_data_valid();
    } else if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out1) {
      aead_read_data_block(dec1);
      got_out1 = 1;
      aead_clear_data_valid();
    }
    if ((status & AEAD_ST_GIFT_AD_REQ) && !ad_sent) {
      AEAD_AD(0) = blk1_1b[0];
      AEAD_AD(1) = blk1_1b[1];
      AEAD_AD(2) = blk1_1b[2];
      AEAD_AD(3) = blk1_1b[3];
      aead_gift_ack_ad();
      ad_sent = 1;
    }
    if ((status & AEAD_ST_GIFT_MSG_REQ) && !msg_sent) {
      AEAD_DIN(0) = ct_blk1_exp[0];
      AEAD_DIN(1) = ct_blk1_exp[1];
      AEAD_DIN(2) = ct_blk1_exp[2];
      AEAD_DIN(3) = ct_blk1_exp[3];
      aead_gift_ack_msg();
      msg_sent = 1;
    }
  }
  run_wait_cycles = rdcycle32() - wait_begin;
  status = AEAD_STREAM_STATUS;
  if ((status & AEAD_ST_GIFT_DATA_VALID) && !got_out1) {
    aead_read_data_block(dec1);
    got_out1 = 1;
    aead_clear_data_valid();
  }
  run_total_cycles = rdcycle32() - op_begin;
  run_core_cycles = aead_last_core_cycles(2u);

  ps("PT blk0      : ");
  p128(dec0);
  pc('\n');
  ps("PT blk1      : ");
  ph(dec1[3]);
  pc('\n');
  ps("Valid        : ");
  pc((AEAD_CTRL & 0x80) ? '1' : '0');
  pc('\n');
  ps("DECRYPT      : ");
  if ((AEAD_CTRL & 0x80) && got_out0 && got_out1 && eq128(dec0, blk0_16) &&
      eq128(dec1, blk1_1b)) {
    ps("PASS\n");
  } else {
    ps("FAIL\n");
    all_ok = 0;
  }
  perf_print_one("GIFT-COFB", "decrypt_17B", 17u, run_core_cycles,
                 run_wait_cycles, run_total_cycles, aead_est_fmax_khz(2u));
  perf_update(&perf_giftcofb, 17u, run_core_cycles, run_wait_cycles,
              run_total_cycles);
  ps("----------------------------------------\n");
  ps(all_ok ? "GIFT-COFB: 2/2 PASSED\n\n" : "GIFT-COFB: SOME TESTS FAILED\n\n");

  *pass = all_ok;
}

/* ====================================================
 * SD Card over SPI (raw sector read demo)
 * Memory map:
 *   0x6000_0000 DATA    [7:0] tx/rx
 *   0x6000_0004 STATUS  [2]=cs_n [1]=busy [0]=done
 *   0x6000_0008 CTRL    [0]=cs_n
 *   0x6000_000C CLKDIV  [15:0] half-period divider
 * ==================================================== */
#if !SKIP_SD_TEST
#define SDSPI(off) (*(volatile uint32_t *)(0x60000000 + (off)))
#define SDSPI_DATA SDSPI(0x00)
#define SDSPI_STATUS SDSPI(0x04)
#define SDSPI_CTRL SDSPI(0x08)
#define SDSPI_CLKDIV SDSPI(0x0C)

#define SDSPI_ST_DONE 0x01
#define SDSPI_ST_BUSY 0x02

static int sd_is_sdhc = 0;
static uint8_t sd_sector0[512];

static void ph8(uint8_t v) {
  const char h[] = "0123456789abcdef";
  pc(h[(v >> 4) & 0xF]);
  pc(h[v & 0xF]);
}

static void dump_bytes(const uint8_t *buf, int count) {
  for (int i = 0; i < count; i++) {
    if ((i & 15) == 0) {
      pc('\n');
      ps("#   ");
    }
    ph8(buf[i]);
    pc(' ');
  }
  pc('\n');
}

static void sd_spi_set_div(uint16_t div) { SDSPI_CLKDIV = div; }

static void sd_spi_cs(int high) { SDSPI_CTRL = high ? 1u : 0u; }

static uint8_t sd_spi_xfer(uint8_t tx) {
  while (SDSPI_STATUS & SDSPI_ST_BUSY)
    ;
  SDSPI_DATA = tx;
  while (!(SDSPI_STATUS & SDSPI_ST_DONE))
    ;
  return (uint8_t)(SDSPI_DATA & 0xFF);
}

static int sd_wait_ready(uint32_t limit) {
  while (limit--) {
    if (sd_spi_xfer(0xFF) == 0xFF)
      return 1;
  }
  return 0;
}

static void sd_deselect(void) {
  sd_spi_cs(1);
  sd_spi_xfer(0xFF);
}

static int sd_select(void) {
  sd_spi_cs(0);
  sd_spi_xfer(0xFF);
  return sd_wait_ready(50000);
}

static uint8_t sd_send_cmd(uint8_t cmd, uint32_t arg, uint8_t crc) {
  uint8_t res;

  if (cmd & 0x80) {
    cmd &= 0x7F;
    res = sd_send_cmd(55, 0, 0x01);
    if (res > 1)
      return res;
  }

  sd_deselect();
  if (!sd_select())
    return 0xFF;

  sd_spi_xfer(0x40 | cmd);
  sd_spi_xfer((uint8_t)(arg >> 24));
  sd_spi_xfer((uint8_t)(arg >> 16));
  sd_spi_xfer((uint8_t)(arg >> 8));
  sd_spi_xfer((uint8_t)arg);
  sd_spi_xfer(crc);

  for (int i = 0; i < 10; i++) {
    res = sd_spi_xfer(0xFF);
    if ((res & 0x80) == 0)
      return res;
  }
  return 0xFF;
}

static int sd_init_card(void) {
  uint8_t r;
  uint8_t ocr[4];

  sd_spi_set_div(199); /* 100 MHz / (2*(199+1)) = 250 kHz */
  sd_spi_cs(1);
  for (int i = 0; i < 80; i++)
    sd_spi_xfer(0xFF);

  r = 0xFF;
  for (int retry = 0; retry < 5 && r != 0x01; retry++) {
    r = sd_send_cmd(0, 0, 0x95);
    if (r != 0x01)
      sd_deselect();
  }
  if (r != 0x01) {
    sd_deselect();
    return 0;
  }

  r = sd_send_cmd(8, 0x000001AA, 0x87);
  if (r == 0x01) {
    for (int i = 0; i < 4; i++)
      ocr[i] = sd_spi_xfer(0xFF);
    if (ocr[2] != 0x01 || ocr[3] != 0xAA) {
      sd_deselect();
      return 0;
    }

    int ready = 0;
    for (uint32_t retry = 0; retry < 20000; retry++) {
      r = sd_send_cmd(0x80 | 41, 0x40000000, 0x01);
      if (r == 0x00) {
        ready = 1;
        break;
      }
    }
    if (!ready) {
      sd_deselect();
      return 0;
    }

    if (sd_send_cmd(58, 0, 0x01) != 0x00) {
      sd_deselect();
      return 0;
    }
    for (int i = 0; i < 4; i++)
      ocr[i] = sd_spi_xfer(0xFF);
    sd_is_sdhc = (ocr[0] & 0x40) ? 1 : 0;
  } else {
    int ready = 0;
    for (uint32_t retry = 0; retry < 20000; retry++) {
      r = sd_send_cmd(0x80 | 41, 0x00000000, 0x01);
      if (r == 0x00) {
        ready = 1;
        break;
      }
    }
    if (!ready) {
      sd_deselect();
      return 0;
    }
    if (sd_send_cmd(16, 512, 0x01) != 0x00) {
      sd_deselect();
      return 0;
    }
    sd_is_sdhc = 0;
  }

  sd_deselect();
  sd_spi_set_div(4); /* 100 MHz / (2*(4+1)) = 10 MHz */
  return 1;
}

static int sd_read_block(uint32_t lba, uint8_t *buf) {
  uint32_t addr = sd_is_sdhc ? lba : (lba << 9);

  if (sd_send_cmd(17, addr, 0x01) != 0x00) {
    sd_deselect();
    return 0;
  }

  uint8_t token = 0xFF;
  for (uint32_t retry = 0; retry < 200000; retry++) {
    token = sd_spi_xfer(0xFF);
    if (token == 0xFE)
      break;
  }
  if (token != 0xFE) {
    sd_deselect();
    return 0;
  }

  for (int i = 0; i < 512; i++)
    buf[i] = sd_spi_xfer(0xFF);

  sd_spi_xfer(0xFF); /* CRC16[15:8] */
  sd_spi_xfer(0xFF); /* CRC16[7:0]  */
  sd_deselect();
  return 1;
}

static void test_sdcard(int *pass) {
  ps("# [SD] SPI raw sector read\n");
  ln();

  if (!sd_init_card()) {
    ps("# SD init: FAIL\n");
    ln();
    *pass = 0;
    return;
  }

  ps("# SD init: PASS\n");
  ps("# Card type: ");
  ps(sd_is_sdhc ? "SDHC/SDXC\n" : "SDSC\n");

  if (!sd_read_block(0, sd_sector0)) {
    ps("# CMD17 sector 0: FAIL\n");
    ln();
    *pass = 0;
    return;
  }

  ps("# CMD17 sector 0: PASS\n");
  ps("# Sector0[510:511] signature: ");
  ph8(sd_sector0[510]);
  ph8(sd_sector0[511]);
  pc('\n');
  ps("# First 64 bytes of sector 0:");
  dump_bytes(sd_sector0, 64);

  *pass = (sd_sector0[510] == 0x55 && sd_sector0[511] == 0xAA);
  ps(*pass ? "# SD sector read: PASS\n"
           : "# SD sector read: WARN (no 0x55AA signature)\n");
  ln();
}
#endif

/* ====================================================
 * MAIN
 * ==================================================== */
int main(void) {
  OUTBYTE = 0x01;
  for (volatile int i = 0; i < 500000; i++)
    ;

  int jb_pass = 0, xd_pass = 0, gc_pass = 0, sd_pass = 0;

  ps("\n\n");
  ps("# ======================================\n");
  ps("# PicoRV32 Crypto SoC + SD SPI\n");
  ps("# AEAD Cluster       @ 0x3000_0000\n");
  ps("#  - 0: TinyJAMBU\n");
  ps("#  - 1: Xoodyak\n");
  ps("#  - 2: GIFT-COFB\n");
  ps("# SD SPI:            @ 0x6000_0000\n");
  ps("# Arty A7-100T  |  100 MHz\n");
  ps("# Throughput modes:\n");
  ps("#   core  = hardware cycles from AEAD start to done\n");
  ps("#   wait  = CPU cycles from AEAD_CTRL start until done observed\n");
  ps("#   total = CPU cycles for input writes + wait + result reads\n");

  ps("# ======================================\n\n");

  test_tinyjambu(&jb_pass);
  ps("\n");
  test_xoodyak(&xd_pass);
  ps("\n");
  test_giftcofb(&gc_pass);
  ps("\n");
#if SKIP_SD_TEST
  sd_pass = 1;
#else
  test_sdcard(&sd_pass);
#endif

  ps("\n");
  ps("# ======================================\n");
  ps("# Throughput Summary\n");
  perf_print_summary("TinyJAMBU", &perf_tinyjambu, aead_est_fmax_khz(0u));
  perf_print_summary("Xoodyak", &perf_xoodyak, aead_est_fmax_khz(1u));
  perf_print_summary("GIFT-COFB", &perf_giftcofb, aead_est_fmax_khz(2u));
  perf_print_summary("System-All", &perf_all, 0u);

  ps("\n");
  ps("# ======================================\n");
  int all = jb_pass && xd_pass && gc_pass && sd_pass;
  if (all) {
    ps("# RESULT: ALL CRYPTO CORES + SD PASS\n");
    OUTBYTE = 0xFF;
  } else {
    ps("# RESULT: SOME TESTS FAILED\n");
    if (!jb_pass)
      ps("#   TinyJAMBU: FAIL\n");
    if (!xd_pass)
      ps("#   Xoodyak:   FAIL\n");
    if (!gc_pass)
      ps("#   GIFT-COFB: FAIL\n");
    if (!sd_pass)
      ps("#   SD SPI:    FAIL\n");
    OUTBYTE = 0x55;
  }
  ps("# ======================================\n");
  while (1)
    ;
}
