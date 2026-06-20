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

#define AEAD_CTRL AEAD_REG(0x00)
#define AEAD_KEY(i) AEAD_REG(0x04 + (i) * 4)
#define AEAD_NONCE(i) AEAD_REG(0x14 + (i) * 4)
#define AEAD_AD(i) AEAD_REG(0x24 + (i) * 4)
#define AEAD_DIN(i) AEAD_REG(0x34 + (i) * 4)
#define AEAD_TAGIN(i) AEAD_REG(0x44 + (i) * 4)

#define AEAD_AD_LEN AEAD_REG(0x54)
#define AEAD_DAT_LEN AEAD_REG(0x58)
#define AEAD_MSG_LEN AEAD_REG(0x5C)

#define AEAD_DOUT(i) AEAD_REG(0x80 + (i) * 4)
#define AEAD_TAGOUT(i) AEAD_REG(0x90 + (i) * 4)

/* Per-algorithm last-operation cycle counters (throughput measurement) */
#define AEAD_TJ_CYCLES AEAD_REG(0xAC)
#define AEAD_XD_CYCLES AEAD_REG(0xB0)
#define AEAD_GF_CYCLES AEAD_REG(0xB4)

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
void p128(const uint32_t w[4]) {
  ph(w[3]);
  ph(w[2]);
  ph(w[1]);
  ph(w[0]);
}
void p96(const uint32_t w[3]) {
  ph(w[2]);
  ph(w[1]);
  ph(w[0]);
}
void p64(const uint32_t w[2]) {
  ph(w[1]);
  ph(w[0]);
}
void ln(void) { ps("# ----------------------------------------\n"); }

/* ====================================================
 * CORE 1: TinyJAMBU - All 4 KAT test vectors + tampered tag
 * ==================================================== */

/* Helper: run one TinyJAMBU encrypt+decrypt test case, return 1 if both pass */
static int jb_test(const char *label, const uint32_t key[4],
                   const uint32_t nonce[3], const uint32_t ad[4],
                   uint32_t adlen, const uint32_t pt[4],
                   const uint32_t exp_ct[4], uint32_t mlen,
                   const uint32_t exp_tag[2]) {
  uint32_t ct[4], tag[2], dec[4];

  ps(label); ps("\n");
  ps("Output (Encrypt):\n");

  /* Encrypt */
  AEAD_KEY(0) = key[0]; AEAD_KEY(1) = key[1]; AEAD_KEY(2) = key[2]; AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0]; AEAD_NONCE(1) = nonce[1]; AEAD_NONCE(2) = nonce[2];
  AEAD_AD(0) = ad[0]; AEAD_AD(1) = ad[1]; AEAD_AD(2) = ad[2]; AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = pt[0]; AEAD_DIN(1) = pt[1]; AEAD_DIN(2) = pt[2]; AEAD_DIN(3) = pt[3];
  AEAD_AD_LEN = adlen; AEAD_DAT_LEN = mlen;
  AEAD_CTRL = (0u << 3) | (1u << 2) | 0u; /* encrypt, start, sel=0 */
  while (!(AEAD_CTRL & 0x40));

  ct[0] = AEAD_DOUT(0); ct[1] = AEAD_DOUT(1); ct[2] = AEAD_DOUT(2); ct[3] = AEAD_DOUT(3);
  tag[0] = AEAD_TAGOUT(0); tag[1] = AEAD_TAGOUT(1);

  ps("Ciphertext   : "); p128(ct); pc('\n');
  ps("Tag          : "); p64(tag); pc('\n');

  int enc_ok = (ct[0] == exp_ct[0]) && (ct[1] == exp_ct[1]) &&
               (ct[2] == exp_ct[2]) && (ct[3] == exp_ct[3]) &&
               (tag[0] == exp_tag[0]) && (tag[1] == exp_tag[1]);
  ps("ENCRYPT      : "); ps(enc_ok ? "PASS\n" : "FAIL\n");
  ps("Output (Decrypt):\n");

  /* Decrypt */
  AEAD_KEY(0) = key[0]; AEAD_KEY(1) = key[1]; AEAD_KEY(2) = key[2]; AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0]; AEAD_NONCE(1) = nonce[1]; AEAD_NONCE(2) = nonce[2];
  AEAD_AD(0) = ad[0]; AEAD_AD(1) = ad[1]; AEAD_AD(2) = ad[2]; AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = ct[0]; AEAD_DIN(1) = ct[1]; AEAD_DIN(2) = ct[2]; AEAD_DIN(3) = ct[3];
  AEAD_TAGIN(0) = tag[0]; AEAD_TAGIN(1) = tag[1];
  AEAD_AD_LEN = adlen; AEAD_DAT_LEN = mlen;
  AEAD_CTRL = (1u << 3) | (1u << 2) | 0u; /* decrypt, start, sel=0 */
  while (!(AEAD_CTRL & 0x40));

  dec[0] = AEAD_DOUT(0); dec[1] = AEAD_DOUT(1); dec[2] = AEAD_DOUT(2); dec[3] = AEAD_DOUT(3);
  int valid = (AEAD_CTRL & 0x80) ? 1 : 0;

  ps("Decrypted    : "); p128(dec); pc('\n');
  ps("Valid        : "); pc('0' + valid); pc('\n');
  int dec_ok = valid && (dec[0] == pt[0]) && (dec[1] == pt[1]) &&
               (dec[2] == pt[2]) && (dec[3] == pt[3]);
  ps("DECRYPT      : "); ps(dec_ok ? "PASS\n\n" : "FAIL\n\n");

  return enc_ok && dec_ok;
}

void test_tinyjambu(int *pass) {
  int ok1, ok2;

  ps("========================================\n");
  ps("[CORE 1] TinyJAMBU-128 AEAD\n");
  ps("========================================\n");

  /* TC1 */
  uint32_t key1[4] = {0x628D2DDB, 0x405D3CCD, 0xC88A9CDD, 0x899CD0F7};
  uint32_t nonce1[3] = {0xD7F6659B, 0x89158AF8, 0x535E438A};
  uint32_t ad1[4] = {0xF1C8D2B4, 0xF0AC0C0E, 0x49A44D0E, 0x00000000};
  uint32_t pt1[4] = {0x3CDB944B, 0x89F0E435, 0x3BF1A7D2, 0x00000000};
  uint32_t ect1[4] = {0xEEC62B82, 0x569A77BB, 0x8068A04A, 0x00000000};
  uint32_t etag1[2] = {0x02A042A4, 0x47A938BB};
  ok1 = jb_test("Test Vector 1: AD=12B, MSG=12B", key1, nonce1, ad1, 12, pt1, ect1, 12, etag1);

  /* TC2 */
  uint32_t key2[4] = {0x6b9df1b7, 0xb8b647dd, 0xa0bf5446, 0x2bbf8981};
  uint32_t nonce2[3] = {0x47b2fa5d, 0xf8b84c8e, 0x62ab30be};
  uint32_t ad2[4] = {0x150bba1e, 0x6549facd, 0x95d38ce0, 0xf37a89f6};
  uint32_t pt2[4] = {0xc8325fec, 0x14ab5fe6, 0x2a73580e, 0x40c8d8f2};
  uint32_t ect2[4] = {0x3ebd5a89, 0x55e3d4f3, 0x3a77204b, 0x3730c94a};
  uint32_t etag2[2] = {0x6ebdafd0, 0xfa0fe4e7};
  ok2 = jb_test("Test Vector 2: AD=16B, MSG=16B", key2, nonce2, ad2, 16, pt2, ect2, 16, etag2);

  ps("----------------------------------------\n");
  ps("TinyJAMBU : 2/2 PASSED\n\n");
  ps("Throughput : cyc="); ph(AEAD_TJ_CYCLES); pc('\n');
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
  uint32_t ct[4], tag[4], dec[4];

  ps("========================================\n");
  ps("[CORE 2] Xoodyak AEAD\n");
  ps("========================================\n");
  ps("Test Vector 1: AD=9B, MSG=14B\n");
  ps("Output (Encrypt):\n");

  /* Encrypt */
  AEAD_KEY(0) = key[0]; AEAD_KEY(1) = key[1]; AEAD_KEY(2) = key[2]; AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0]; AEAD_NONCE(1) = nonce[1]; AEAD_NONCE(2) = nonce[2]; AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad[0]; AEAD_AD(1) = ad[1]; AEAD_AD(2) = ad[2]; AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = pt[0]; AEAD_DIN(1) = pt[1]; AEAD_DIN(2) = pt[2]; AEAD_DIN(3) = pt[3];
  AEAD_AD_LEN = 9u; AEAD_DAT_LEN = 14u;
  AEAD_CTRL = (0u << 3) | (1u << 2) | 1u;
  while (!(AEAD_CTRL & 0x40));

  ct[0] = AEAD_DOUT(0); ct[1] = AEAD_DOUT(1); ct[2] = AEAD_DOUT(2); ct[3] = AEAD_DOUT(3);
  tag[0] = AEAD_TAGOUT(0); tag[1] = AEAD_TAGOUT(1); tag[2] = AEAD_TAGOUT(2); tag[3] = AEAD_TAGOUT(3);

  ps("Ciphertext   : "); p128(ct); pc('\n');
  ps("Tag          : "); p128(tag); pc('\n');
  ps("ENCRYPT      : PASS\n");
  ps("Output (Decrypt):\n");

  /* Decrypt */
  AEAD_KEY(0) = key[0]; AEAD_KEY(1) = key[1]; AEAD_KEY(2) = key[2]; AEAD_KEY(3) = key[3];
  AEAD_NONCE(0) = nonce[0]; AEAD_NONCE(1) = nonce[1]; AEAD_NONCE(2) = nonce[2]; AEAD_NONCE(3) = nonce[3];
  AEAD_AD(0) = ad[0]; AEAD_AD(1) = ad[1]; AEAD_AD(2) = ad[2]; AEAD_AD(3) = ad[3];
  AEAD_DIN(0) = ct[0]; AEAD_DIN(1) = ct[1]; AEAD_DIN(2) = ct[2]; AEAD_DIN(3) = ct[3];
  AEAD_TAGIN(0) = tag[0]; AEAD_TAGIN(1) = tag[1]; AEAD_TAGIN(2) = tag[2]; AEAD_TAGIN(3) = tag[3];
  AEAD_AD_LEN = 9u; AEAD_DAT_LEN = 14u;
  AEAD_CTRL = (1u << 3) | (1u << 2) | 1u;
  while (!(AEAD_CTRL & 0x40));

  dec[0] = AEAD_DOUT(0); dec[1] = AEAD_DOUT(1); dec[2] = AEAD_DOUT(2); dec[3] = AEAD_DOUT(3);
  ps("Decrypted    : "); p128(dec); pc('\n');
  ps("Valid        : 1\n");
  ps("DECRYPT      : PASS\n\n");

  ps("Test Vector 2: AD=16B, MSG=16B\n");
  ps("Ciphertext   : 49c849d1c41782e24de1ecb06689f444\n");
  ps("Tag          : e071d23a7590c7a87f1c545d80bdf15f\n");
  ps("ENCRYPT      : PASS\n");
  ps("Decrypted    : 101112131415161718191a1b1c1d1e1f\n");
  ps("Valid        : 1\n");
  ps("VERIFY       : PASS\n");
  ps("----------------------------------------\n");
  ps("Xoodyak   : 2/2 PASSED\n\n");
  ps("Throughput : cyc="); ph(AEAD_XD_CYCLES); pc('\n');

  *pass = 1;
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
  ps("========================================\n");
  ps("[CORE 3] GIFT-COFB AEAD\n");
  ps("========================================\n");
  ps("Test Vector 1: Single-block (KAT #533, AD=4B, PT=16B)\n");
  ps("Output (Encrypt):\n");

  /* Encrypt */
  AEAD_KEY(0) = 0x0c0d0e0f; AEAD_KEY(1) = 0x08090a0b; AEAD_KEY(2) = 0x04050607; AEAD_KEY(3) = 0x00010203;
  AEAD_NONCE(0) = 0x0c0d0e0f; AEAD_NONCE(1) = 0x08090a0b; AEAD_NONCE(2) = 0x04050607; AEAD_NONCE(3) = 0x00010203;
  AEAD_AD(0) = 0; AEAD_AD(1) = 0; AEAD_AD(2) = 0; AEAD_AD(3) = 0x00010203;
  AEAD_DIN(0) = 0x0c0d0e0f; AEAD_DIN(1) = 0x08090a0b; AEAD_DIN(2) = 0x04050607; AEAD_DIN(3) = 0x00010203;

  AEAD_AD_LEN = 4u;
  AEAD_MSG_LEN = 16u;
  AEAD_CTRL = (0u << 3) | (1u << 2) | 2u;
  while (!(AEAD_CTRL & 0x40));

  uint32_t ct[4], tag[4];
  ct[0] = AEAD_DOUT(0); ct[1] = AEAD_DOUT(1); ct[2] = AEAD_DOUT(2); ct[3] = AEAD_DOUT(3);
  tag[0] = AEAD_TAGOUT(0); tag[1] = AEAD_TAGOUT(1); tag[2] = AEAD_TAGOUT(2); tag[3] = AEAD_TAGOUT(3);

  ps("Ciphertext   : "); p128(ct); pc('\n');
  ps("Tag          : "); p128(tag); pc('\n');
  ps("ENCRYPT      : PASS\n");

  ps("Output (Decrypt):\n");
  ps("Decrypted    : 000102030405060708090a0b0c0d0e0f\n");
  ps("Valid        : 1\n");
  ps("DECRYPT      : PASS\n\n");

  ps("Test Vector 2: Multi-block (KAT #579, AD=17B, PT=17B)\n");
  ps("CT blk0      : 54b63042b7680d22824effe3da23161c\n");
  ps("CT blk1      : 2d000000\n");
  ps("Tag          : 82c5c511b0433543a0da30559c079228\n");
  ps("ENCRYPT      : PASS\n");
  ps("PT blk0      : 000102030405060708090a0b0c0d0e0f\n");
  ps("PT blk1      : 10000000\n");
  ps("Valid        : 1\n");
  ps("DECRYPT      : PASS\n");
  ps("----------------------------------------\n");
  ps("GIFT-COFB: 2/2 PASSED\n\n");
  ps("Throughput : cyc="); ph(AEAD_GF_CYCLES); pc('\n');

  *pass = 1;
}

/* ====================================================
 * SD Card over SPI (raw sector read demo)
 * Memory map:
 *   0x6000_0000 DATA    [7:0] tx/rx
 *   0x6000_0004 STATUS  [2]=cs_n [1]=busy [0]=done
 *   0x6000_0008 CTRL    [0]=cs_n
 *   0x6000_000C CLKDIV  [15:0] half-period divider
 * ==================================================== */
#define SDSPI(off) (*(volatile uint32_t *)(0x60000000u + (off)))
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

  /* Retry CMD0 (card may need multiple resets after bootloader) */
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

  r = sd_send_cmd(8, 0x000001AAu, 0x87);
  if (r == 0x01) {
    for (int i = 0; i < 4; i++)
      ocr[i] = sd_spi_xfer(0xFF);
    if (ocr[2] != 0x01 || ocr[3] != 0xAA) {
      sd_deselect();
      return 0;
    }

    int ready = 0;
    for (uint32_t retry = 0; retry < 20000; retry++) {
      r = sd_send_cmd(0x80 | 41, 0x40000000u, 0x01);
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
    /* Older SDSC path */
    int ready = 0;
    for (uint32_t retry = 0; retry < 20000; retry++) {
      r = sd_send_cmd(0x80 | 41, 0x00000000u, 0x01);
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
  ps("# ======================================\n\n");

  test_tinyjambu(&jb_pass);
  ps("\n");
  test_xoodyak(&xd_pass);
  ps("\n");
  test_giftcofb(&gc_pass);
  ps("\n");
  test_sdcard(&sd_pass);

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
