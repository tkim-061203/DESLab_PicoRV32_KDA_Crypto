/*
 * ============================================================
 * IoT Secure Gateway — PicoSoC Firmware
 * ============================================================
 * Đọc dữ liệu sensor → Mã hóa bằng hardware crypto → Gửi UART
 *
 * Flow:
 *   1. Khởi tạo UART, sensor, crypto key
 *   2. Vòng lặp chính:
 *      a. Thu thập dữ liệu sensor (switches, buttons, temp, humid)
 *      b. Đóng gói thành plaintext block 16 bytes
 *      c. Mã hóa bằng TinyJAMBU / Xoodyak / GIFT-COFB
 *      d. Gửi packet mã hóa qua UART (định dạng hex)
 *      e. Chờ interval, lặp lại
 *
 * UART Output format (mỗi packet):
 *   [PKT|<seq>|<algo>|<nonce_hex>|<ct_hex>|<tag_hex>|<crc8>]\n
 *
 * Memory Map (từ system.v):
 *   0x1000_0000  LED / GPIO output
 *   0x1000_0004  UART TX
 *   0x1000_000C  UART Status
 *   0x1000_0010  UART Baud Divider
 *   0x2000_0000  Switches (4-bit)
 *   0x2000_0004  Buttons  (4-bit)
 *   0x3000_0000  TinyJAMBU registers
 *   0x4000_0000  Xoodyak registers
 *   0x5000_0000  GIFT-COFB registers
 * ============================================================
 */

#include <stdint.h>

/* ---- Hardware registers ---- */
#define OUTBYTE    (*(volatile uint32_t *)0x10000000)
#define UART_TX    (*(volatile uint32_t *)0x10000004)
#define UART_RX    (*(volatile uint32_t *)0x10000008)
#define UART_ST    (*(volatile uint32_t *)0x1000000C)
#define UART_DIV   (*(volatile uint32_t *)0x10000010)
#define SW_REG     (*(volatile uint32_t *)0x20000000)
#define BTN_REG    (*(volatile uint32_t *)0x20000004)

/* TinyJAMBU (base 0x3000_0000) */
#define JB(off)    (*(volatile uint32_t *)(0x30000000 + (off)))
#define JB_CTRL    JB(0x44)
#define JB_STATUS  JB(0x48)

/* Xoodyak (base 0x4000_0000) */
#define XD(off)    (*(volatile uint32_t *)(0x40000000 + (off)))
#define XD_CTRL    XD(0x50)
#define XD_STATUS  XD(0x54)

/* GIFT-COFB (base 0x5000_0000) */
#define GC(off)    (*(volatile uint32_t *)(0x50000000 + (off)))
#define GC_CTRL    GC(0x50)
#define GC_STATUS  GC(0x54)

/* ============================================================
 * UART I/O
 * ============================================================ */
static void uart_putc(char c) {
    if (c == '\n') {
        while (!(UART_ST & 1));
        UART_TX = '\r';
    }
    while (!(UART_ST & 1));
    UART_TX = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_puthex8(uint8_t v) {
    const char h[] = "0123456789abcdef";
    uart_putc(h[(v >> 4) & 0xF]);
    uart_putc(h[v & 0xF]);
}

static void uart_puthex32(uint32_t v) {
    const char h[] = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(h[(v >> i) & 0xF]);
}

static void uart_putdec(uint32_t v) {
    char buf[10];
    int i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v > 0) {
        buf[i++] = '0' + (v % 10);
        v /= 10;
    }
    while (--i >= 0)
        uart_putc(buf[i]);
}

/* ============================================================
 * Simple CRC-8 (polynomial 0x07) for packet integrity
 * ============================================================ */
static uint8_t crc8_update(uint8_t crc, uint8_t data) {
    crc ^= data;
    for (int i = 0; i < 8; i++) {
        if (crc & 0x80)
            crc = (crc << 1) ^ 0x07;
        else
            crc <<= 1;
    }
    return crc;
}

static uint8_t crc8_buf(const uint8_t *buf, int len) {
    uint8_t crc = 0x00;
    for (int i = 0; i < len; i++)
        crc = crc8_update(crc, buf[i]);
    return crc;
}

/* ============================================================
 * PRNG — xorshift32 (dùng làm sensor giả lập + nonce counter)
 * ============================================================ */
static uint32_t prng_state = 0xDEADBEEF;

static uint32_t xorshift32(void) {
    uint32_t x = prng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    prng_state = x;
    return x;
}

/* ============================================================
 * Cycle counter — dùng để đo thời gian mã hóa
 * ============================================================ */
static uint32_t rdcycle(void) {
    uint32_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
}

/* ============================================================
 * Sensor Data Collection
 * ============================================================
 * Plaintext layout (16 bytes / 4 words):
 *   word[0] = [sw:4][btn:4][temp:8][humid:8][light:8]
 *   word[1] = [timestamp_lo:32]
 *   word[2] = [seq_number:32]
 *   word[3] = [device_id:16][status:8][reserved:8]
 * ============================================================ */
#define DEVICE_ID  0x5043   /* "PC" for PicoSoC */

typedef struct {
    uint32_t words[4];
    uint8_t  bytes[16];     /* same data as byte array for CRC */
} sensor_packet_t;

static uint32_t seq_counter = 0;

static void collect_sensor_data(sensor_packet_t *pkt) {
    uint32_t sw   = SW_REG  & 0xF;
    uint32_t btn  = BTN_REG & 0xF;

    /* Simulated analog sensors (in real HW, these would come from
       ADC via SPI or I2C) */
    uint32_t temp  = 22 + (xorshift32() % 15);      /* 22-36 °C   */
    uint32_t humid = 40 + (xorshift32() % 40);       /* 40-79 %RH  */
    uint32_t light = 100 + (xorshift32() % 900);     /* 100-999 lux */

    uint32_t timestamp = rdcycle();

    pkt->words[0] = (sw << 28) | (btn << 24) | ((temp & 0xFF) << 16)
                   | ((humid & 0xFF) << 8) | (light & 0xFF);
    pkt->words[1] = timestamp;
    pkt->words[2] = seq_counter;
    pkt->words[3] = (DEVICE_ID << 16) | (0x01 << 8) | 0x00;  /* status=OK */

    /* Copy to byte array for CRC */
    for (int i = 0; i < 4; i++) {
        uint32_t w = pkt->words[i];
        pkt->bytes[i*4 + 0] = (w >> 24) & 0xFF;
        pkt->bytes[i*4 + 1] = (w >> 16) & 0xFF;
        pkt->bytes[i*4 + 2] = (w >>  8) & 0xFF;
        pkt->bytes[i*4 + 3] = (w >>  0) & 0xFF;
    }

    seq_counter++;
}

/* ============================================================
 * Nonce Management
 * ============================================================
 * Nonce = [device_id : 16][boot_random : 16][counter : 64]
 * Mỗi lần mã hóa, counter tăng 1 → đảm bảo nonce không lặp
 * ============================================================ */
static uint32_t nonce_counter_lo = 0;
static uint32_t nonce_counter_hi = 0;
static uint32_t nonce_random = 0;

static void nonce_init(void) {
    nonce_random = xorshift32();     /* pseudo-random per boot */
    nonce_counter_lo = 0;
    nonce_counter_hi = 0;
}

static void nonce_increment(void) {
    nonce_counter_lo++;
    if (nonce_counter_lo == 0)
        nonce_counter_hi++;
}

/* ============================================================
 * Crypto Encryption — TinyJAMBU
 * ============================================================
 * Key:   128-bit (pre-shared)
 * Nonce: 96-bit  (3 words)
 * AD:    Device header (4 words)
 * PT:    Sensor data   (4 words = 16 bytes)
 * Output: CT (16 bytes) + Tag (8 bytes)
 * ============================================================ */

/* Pre-shared key (in production, this would be in secure storage) */
static const uint32_t master_key[4] = {
    0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF
};

typedef struct {
    uint32_t ct[4];     /* ciphertext (128-bit) */
    uint32_t tag_jb[2]; /* TinyJAMBU tag (64-bit) */
    uint32_t tag128[4]; /* Xoodyak/GIFT-COFB tag (128-bit) */
    uint32_t nonce[4];  /* nonce used */
    uint32_t cycles;    /* encryption time in cycles */
} crypto_result_t;

static void encrypt_tinyjambu(const sensor_packet_t *pkt,
                               const uint32_t ad[4],
                               crypto_result_t *res) {
    uint32_t t0 = rdcycle();

    /* Nonce (96-bit for TinyJAMBU) */
    res->nonce[0] = (DEVICE_ID << 16) | (nonce_random & 0xFFFF);
    res->nonce[1] = nonce_counter_lo;
    res->nonce[2] = nonce_counter_hi;

    /* Load key */
    JB(0x00) = master_key[0];
    JB(0x04) = master_key[1];
    JB(0x08) = master_key[2];
    JB(0x0C) = master_key[3];

    /* Load nonce */
    JB(0x10) = res->nonce[0];
    JB(0x14) = res->nonce[1];
    JB(0x18) = res->nonce[2];

    /* Load AD (associated data = device header, not encrypted) */
    JB(0x1C) = ad[0];
    JB(0x20) = ad[1];
    JB(0x24) = ad[2];
    JB(0x28) = ad[3];

    /* Load plaintext */
    JB(0x2C) = pkt->words[0];
    JB(0x30) = pkt->words[1];
    JB(0x34) = pkt->words[2];
    JB(0x38) = pkt->words[3];

    /* Start encryption: sel_type=1 (encrypt), adlen=16, mlen=16 */
    JB_CTRL = (1u << 16) | (16u << 8) | 16u;

    /* Wait for completion */
    while (!(JB_STATUS & 0x02));

    /* Read results */
    res->ct[0] = JB(0x4C);
    res->ct[1] = JB(0x50);
    res->ct[2] = JB(0x54);
    res->ct[3] = JB(0x58);
    res->tag_jb[0] = JB(0x5C);
    res->tag_jb[1] = JB(0x60);

    res->cycles = rdcycle() - t0;
    nonce_increment();
}

/* ============================================================
 * Crypto Encryption — Xoodyak
 * ============================================================ */
static void encrypt_xoodyak(const sensor_packet_t *pkt,
                             const uint32_t ad[4],
                             crypto_result_t *res) {
    uint32_t t0 = rdcycle();

    /* Nonce (128-bit for Xoodyak) */
    res->nonce[0] = (DEVICE_ID << 16) | (nonce_random & 0xFFFF);
    res->nonce[1] = nonce_counter_lo;
    res->nonce[2] = nonce_counter_hi;
    res->nonce[3] = 0xA5A5A5A5;   /* fixed pad */

    /* Load key */
    XD(0x00) = master_key[0];
    XD(0x04) = master_key[1];
    XD(0x08) = master_key[2];
    XD(0x0C) = master_key[3];

    /* Load nonce */
    XD(0x10) = res->nonce[0];
    XD(0x14) = res->nonce[1];
    XD(0x18) = res->nonce[2];
    XD(0x1C) = res->nonce[3];

    /* Load AD */
    XD(0x20) = ad[0];
    XD(0x24) = ad[1];
    XD(0x28) = ad[2];
    XD(0x2C) = ad[3];

    /* Load plaintext */
    XD(0x30) = pkt->words[0];
    XD(0x34) = pkt->words[1];
    XD(0x38) = pkt->words[2];
    XD(0x3C) = pkt->words[3];

    /* Clear tag_in */
    XD(0x40) = 0;
    XD(0x44) = 0;
    XD(0x48) = 0;
    XD(0x4C) = 0;

    /* Start: sel_type=1 (encrypt), adlen=16, data_len=16 */
    XD_CTRL = (1u << 16) | (16u << 8) | 16u;

    while (!(XD_STATUS & 0x02));

    res->ct[0] = XD(0x58);
    res->ct[1] = XD(0x5C);
    res->ct[2] = XD(0x60);
    res->ct[3] = XD(0x64);
    res->tag128[0] = XD(0x68);
    res->tag128[1] = XD(0x6C);
    res->tag128[2] = XD(0x70);
    res->tag128[3] = XD(0x74);

    res->cycles = rdcycle() - t0;
    nonce_increment();
}

/* ============================================================
 * Crypto Encryption — GIFT-COFB
 * ============================================================ */
static void encrypt_giftcofb(const sensor_packet_t *pkt,
                              const uint32_t ad[4],
                              crypto_result_t *res) {
    uint32_t t0 = rdcycle();

    /* Nonce (128-bit) */
    res->nonce[0] = (DEVICE_ID << 16) | (nonce_random & 0xFFFF);
    res->nonce[1] = nonce_counter_lo;
    res->nonce[2] = nonce_counter_hi;
    res->nonce[3] = 0x5A5A5A5A;

    /* Load key */
    GC(0x00) = master_key[0];
    GC(0x04) = master_key[1];
    GC(0x08) = master_key[2];
    GC(0x0C) = master_key[3];

    /* Load nonce */
    GC(0x10) = res->nonce[0];
    GC(0x14) = res->nonce[1];
    GC(0x18) = res->nonce[2];
    GC(0x1C) = res->nonce[3];

    /* Load AD */
    GC(0x20) = ad[0];
    GC(0x24) = ad[1];
    GC(0x28) = ad[2];
    GC(0x2C) = ad[3];

    /* Load plaintext */
    GC(0x30) = pkt->words[0];
    GC(0x34) = pkt->words[1];
    GC(0x38) = pkt->words[2];
    GC(0x3C) = pkt->words[3];

    /* Clear tag_in */
    GC(0x40) = 0;
    GC(0x44) = 0;
    GC(0x48) = 0;
    GC(0x4C) = 0;

    /* Start: decrypt_mode=0, ad_length=16, data_length=16 */
    GC_CTRL = (0u << 16) | (16u << 8) | 16u;

    while (!(GC_STATUS & 0x02));

    res->ct[0] = GC(0x58);
    res->ct[1] = GC(0x5C);
    res->ct[2] = GC(0x60);
    res->ct[3] = GC(0x64);
    res->tag128[0] = GC(0x68);
    res->tag128[1] = GC(0x6C);
    res->tag128[2] = GC(0x70);
    res->tag128[3] = GC(0x74);

    res->cycles = rdcycle() - t0;
    nonce_increment();
}

/* ============================================================
 * Transmit encrypted packet via UART
 * ============================================================
 * Format:
 *   [PKT|<seq>|<algo>|<nonce>|<ct>|<tag>|<crc8>]\n
 *
 * Ví dụ:
 *   [PKT|42|JB|5043beef00000001|aabb...|1122...|f3]
 * ============================================================ */

static void send_packet(uint32_t seq, const char *algo,
                        const crypto_result_t *res,
                        int nonce_words, int tag_words) {
    /* Build raw byte buffer for CRC */
    uint8_t raw[64];
    int rlen = 0;

    /* Nonce bytes */
    for (int w = 0; w < nonce_words; w++) {
        uint32_t v = res->nonce[w];
        raw[rlen++] = (v >> 24) & 0xFF;
        raw[rlen++] = (v >> 16) & 0xFF;
        raw[rlen++] = (v >>  8) & 0xFF;
        raw[rlen++] = (v >>  0) & 0xFF;
    }
    /* CT bytes */
    for (int w = 0; w < 4; w++) {
        uint32_t v = res->ct[w];
        raw[rlen++] = (v >> 24) & 0xFF;
        raw[rlen++] = (v >> 16) & 0xFF;
        raw[rlen++] = (v >>  8) & 0xFF;
        raw[rlen++] = (v >>  0) & 0xFF;
    }
    /* Tag bytes */
    if (tag_words == 2) {
        for (int w = 0; w < 2; w++) {
            uint32_t v = res->tag_jb[w];
            raw[rlen++] = (v >> 24) & 0xFF;
            raw[rlen++] = (v >> 16) & 0xFF;
            raw[rlen++] = (v >>  8) & 0xFF;
            raw[rlen++] = (v >>  0) & 0xFF;
        }
    } else {
        for (int w = 0; w < 4; w++) {
            uint32_t v = res->tag128[w];
            raw[rlen++] = (v >> 24) & 0xFF;
            raw[rlen++] = (v >> 16) & 0xFF;
            raw[rlen++] = (v >>  8) & 0xFF;
            raw[rlen++] = (v >>  0) & 0xFF;
        }
    }

    uint8_t crc = crc8_buf(raw, rlen);

    /* Transmit */
    uart_puts("[PKT|");
    uart_putdec(seq);
    uart_putc('|');
    uart_puts(algo);
    uart_putc('|');

    /* Nonce */
    for (int w = 0; w < nonce_words; w++)
        uart_puthex32(res->nonce[w]);
    uart_putc('|');

    /* Ciphertext */
    for (int w = 0; w < 4; w++)
        uart_puthex32(res->ct[w]);
    uart_putc('|');

    /* Tag */
    if (tag_words == 2) {
        uart_puthex32(res->tag_jb[0]);
        uart_puthex32(res->tag_jb[1]);
    } else {
        for (int w = 0; w < 4; w++)
            uart_puthex32(res->tag128[w]);
    }
    uart_putc('|');

    /* CRC-8 */
    uart_puthex8(crc);
    uart_puts("]\n");
}

/* ============================================================
 * Print human-readable sensor data (for debugging)
 * ============================================================ */
static void print_sensor_info(const sensor_packet_t *pkt, uint32_t seq) {
    uint32_t w0 = pkt->words[0];
    uint32_t sw   = (w0 >> 28) & 0xF;
    uint32_t btn  = (w0 >> 24) & 0xF;
    uint32_t temp = (w0 >> 16) & 0xFF;
    uint32_t humid = (w0 >> 8) & 0xFF;
    uint32_t light = w0 & 0xFF;

    uart_puts("# --- Sensor Reading #");
    uart_putdec(seq);
    uart_puts(" ---\n");
    uart_puts("#   SW=0x");
    uart_puthex8(sw);
    uart_puts("  BTN=0x");
    uart_puthex8(btn);
    uart_puts("  Temp=");
    uart_putdec(temp);
    uart_puts("C  Humid=");
    uart_putdec(humid);
    uart_puts("%  Light=");
    uart_putdec(light);
    uart_puts(" lux\n");
}

/* ============================================================
 * Print encryption benchmark results
 * ============================================================ */
static void print_bench(const char *name, const crypto_result_t *res) {
    uart_puts("#   ");
    uart_puts(name);
    uart_puts(": ");
    uart_putdec(res->cycles);
    uart_puts(" cycles\n");
}

/* ============================================================
 * Delay function
 * ============================================================ */
static void delay_cycles(uint32_t n) {
    for (volatile uint32_t i = 0; i < n; i++);
}

/* ============================================================
 * Algorithm selection based on switch input
 * ============================================================ */
#define ALGO_TINYJAMBU  0
#define ALGO_XOODYAK    1
#define ALGO_GIFTCOFB   2
#define ALGO_ALL        3   /* mã hóa bằng cả 3 */

static int get_algo_select(void) {
    uint32_t sw = SW_REG & 0x3;  /* 2 bit thấp nhất */
    return (int)sw;
}

/* ============================================================
 * MAIN — IoT Gateway Loop
 * ============================================================ */
int main(void) {
    /* LED startup pattern */
    OUTBYTE = 0x01;

    /* Initialize UART (115200 baud @ 50MHz: div = 50e6/115200 ≈ 434) */
    /* Adjust for your actual clock frequency */

    /* Wait for hardware stabilization */
    delay_cycles(100000);

    /* Initialize nonce */
    nonce_init();

    /* Banner */
    uart_puts("\n\n");
    uart_puts("# =============================================\n");
    uart_puts("#  PicoSoC IoT Secure Gateway v1.0\n");
    uart_puts("# =============================================\n");
    uart_puts("#  Hardware Crypto Accelerators:\n");
    uart_puts("#    [JB] TinyJAMBU   @ 0x3000_0000\n");
    uart_puts("#    [XD] Xoodyak     @ 0x4000_0000\n");
    uart_puts("#    [GC] GIFT-COFB   @ 0x5000_0000\n");
    uart_puts("# ---------------------------------------------\n");
    uart_puts("#  Algorithm select (SW[1:0]):\n");
    uart_puts("#    00 = TinyJAMBU only\n");
    uart_puts("#    01 = Xoodyak only\n");
    uart_puts("#    10 = GIFT-COFB only\n");
    uart_puts("#    11 = All three (benchmark mode)\n");
    uart_puts("# ---------------------------------------------\n");
    uart_puts("#  Pre-shared Key: 00112233_44556677_8899AABB_CCDDEEFF\n");
    uart_puts("#  Device ID: 0x5043 (\"PC\")\n");
    uart_puts("# =============================================\n\n");

    OUTBYTE = 0x0F;

    /* Associated Data — fixed header for all packets. This is
       authenticated but NOT encrypted, so the receiver can identify
       the device without decryption. */
    uint32_t ad[4] = {
        DEVICE_ID << 16 | 0x0001,  /* device_id + protocol version */
        0x00000010,                /* payload size = 16 bytes */
        0x41454144,                /* "AEAD" magic */
        0x00000000                 /* reserved */
    };

    /* Main gateway loop */
    uint32_t loop_count = 0;
    while (1) {
        /* --- 1. Collect sensor data --- */
        sensor_packet_t pkt;
        collect_sensor_data(&pkt);

        /* LED heartbeat */
        OUTBYTE = (loop_count & 1) ? 0xFF : 0x0F;

        /* Print human-readable sensor info */
        print_sensor_info(&pkt, loop_count);

        /* --- 2. Select algorithm and encrypt --- */
        int algo = get_algo_select();
        crypto_result_t res_jb, res_xd, res_gc;

        if (algo == ALGO_TINYJAMBU || algo == ALGO_ALL) {
            encrypt_tinyjambu(&pkt, ad, &res_jb);
            send_packet(loop_count, "JB", &res_jb, 3, 2);
            print_bench("TinyJAMBU", &res_jb);
        }

        if (algo == ALGO_XOODYAK || algo == ALGO_ALL) {
            encrypt_xoodyak(&pkt, ad, &res_xd);
            send_packet(loop_count, "XD", &res_xd, 4, 4);
            print_bench("Xoodyak", &res_xd);
        }

        if (algo == ALGO_GIFTCOFB || algo == ALGO_ALL) {
            encrypt_giftcofb(&pkt, ad, &res_gc);
            send_packet(loop_count, "GC", &res_gc, 4, 4);
            print_bench("GIFT-COFB", &res_gc);
        }

        uart_puts("# ---\n\n");

        /* --- 3. Wait before next reading --- */
        /* ~2 seconds @ 50MHz (adjust for your clock) */
        delay_cycles(2000000);

        loop_count++;
    }
}
