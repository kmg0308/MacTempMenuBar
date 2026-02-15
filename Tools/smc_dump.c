// Minimal SMC key dumper (for discovering temperature keys).
// Works on Apple Silicon too (AppleSMCKeysEndpoint).
//
// Build:
//   clang -O2 -Wall -Wextra -framework IOKit -framework CoreFoundation -o smc_dump smc_dump.c
// Run:
//   ./smc_dump | head

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SMC_MAX_BYTES 32

typedef char SMCBytes_t[SMC_MAX_BYTES];

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

typedef struct {
    uint32_t key;
    uint32_t dataSize;
    uint32_t dataType;
    SMCBytes_t bytes;
} SMCVal_t;

// External method selector used by AppleSMCClient for structured calls.
#define KERNEL_INDEX_SMC 2

// Commands (placed in SMCKeyData_t.data8)
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_GET_KEY_FROM_INDEX 8

static io_connect_t g_conn = IO_OBJECT_NULL;

// Forward declarations.
static kern_return_t smc_read_key_info(uint32_t key, SMCKeyData_keyInfo_t *out_info);
static kern_return_t smc_read_bytes(uint32_t key, const SMCKeyData_keyInfo_t *info, SMCVal_t *out_val);

static uint32_t str_to_key(const char *s) {
    // 4-char code to u32
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

static void key_to_str(uint32_t key, char out[5]) {
    out[0] = (char)((key >> 24) & 0xff);
    out[1] = (char)((key >> 16) & 0xff);
    out[2] = (char)((key >> 8) & 0xff);
    out[3] = (char)(key & 0xff);
    out[4] = '\0';
}

static kern_return_t smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t in_size = sizeof(*in);
    size_t out_size = sizeof(*out);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, in_size, out, &out_size);
}

static kern_return_t smc_read_key(uint32_t key, SMCVal_t *out_val) {
    SMCKeyData_keyInfo_t info = {0};
    kern_return_t kr = smc_read_key_info(key, &info);
    if (kr != KERN_SUCCESS) return kr;
    return smc_read_bytes(key, &info, out_val);
}

static int smc_read_u32(const char *key_str, uint32_t *out_u32) {
    if (strlen(key_str) != 4) return 1;

    uint32_t key = str_to_key(key_str);
    SMCVal_t val = {0};
    kern_return_t kr = smc_read_key(key, &val);
    if (kr != KERN_SUCCESS) return 1;

    if (val.dataSize < 4) return 1;

    const unsigned char *b = (const unsigned char *)val.bytes;
    // Most 4-byte SMC integers are big-endian.
    *out_u32 = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
    return 0;
}

static kern_return_t smc_get_key_from_index(uint32_t index, uint32_t *out_key) {
    SMCKeyData_t in = {0};
    SMCKeyData_t out = {0};

    in.data8 = SMC_CMD_GET_KEY_FROM_INDEX;
    in.data32 = index;

    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return kr;

    *out_key = out.key;
    return KERN_SUCCESS;
}

static kern_return_t smc_read_key_info(uint32_t key, SMCKeyData_keyInfo_t *out_info) {
    SMCKeyData_t in = {0};
    SMCKeyData_t out = {0};

    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return kr;

    *out_info = out.keyInfo;
    return KERN_SUCCESS;
}

static kern_return_t smc_read_bytes(uint32_t key, const SMCKeyData_keyInfo_t *info, SMCVal_t *out_val) {
    SMCKeyData_t in = {0};
    SMCKeyData_t out = {0};

    in.key = key;
    in.keyInfo.dataSize = info->dataSize;
    in.keyInfo.dataType = info->dataType;
    in.data8 = SMC_CMD_READ_BYTES;

    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return kr;

    out_val->key = key;
    out_val->dataSize = info->dataSize;
    out_val->dataType = info->dataType;
    memcpy(out_val->bytes, out.bytes, SMC_MAX_BYTES);

    return KERN_SUCCESS;
}

static int smc_open(void) {
    io_service_t service = IO_OBJECT_NULL;

    // Apple Silicon exposes this as AppleSMCKeysEndpoint.
    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    if (service == IO_OBJECT_NULL) {
        // Some systems may still expose AppleSMC.
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    }
    if (service == IO_OBJECT_NULL) {
        fprintf(stderr, "SMC service not found (AppleSMCKeysEndpoint/AppleSMC)\n");
        return 1;
    }

    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);

    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "IOServiceOpen failed: 0x%x\n", kr);
        return 1;
    }

    return 0;
}

static void smc_close(void) {
    if (g_conn != IO_OBJECT_NULL) {
        IOServiceClose(g_conn);
        g_conn = IO_OBJECT_NULL;
    }
}

static int fourcc_equals(uint32_t v, const char *fourcc) {
    return v == str_to_key(fourcc);
}

static double decode_sp78(const unsigned char *b) {
    // sp78: signed 16-bit fixed point with 8 fractional bits.
    int16_t raw = (int16_t)((b[0] << 8) | b[1]);
    return (double)raw / 256.0;
}

static double decode_flt(const unsigned char *b) {
    float f = 0;
    // On Apple Silicon, "flt " values for temperature keys appear to be little-endian.
    uint32_t u = ((uint32_t)b[3] << 24) | ((uint32_t)b[2] << 16) | ((uint32_t)b[1] << 8) | (uint32_t)b[0];
    memcpy(&f, &u, sizeof(f));
    return (double)f;
}

int main(void) {
    if (smc_open() != 0) return 1;

    uint32_t count = 0;
    if (smc_read_u32("#KEY", &count) != 0 || count == 0) {
        fprintf(stderr, "SMC key count failed (via #KEY).\n");
        smc_close();
        return 1;
    }

    printf("SMC key count: %u\n", count);

    // Dump plausible temperature-like keys.
    const uint32_t max_print = 200;
    uint32_t printed = 0;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t key = 0;
        if (smc_get_key_from_index(i, &key) != KERN_SUCCESS) continue;

        char key_str[5];
        key_to_str(key, key_str);
        // Temperature keys are typically prefixed with 'T' (e.g., TC0P, TG0P, Tp0P).
        if (key_str[0] != 'T' && key_str[0] != 't') {
            continue;
        }

        SMCKeyData_keyInfo_t info = {0};
        if (smc_read_key_info(key, &info) != KERN_SUCCESS) continue;

        // We only care about common temperature encodings.
        if (!fourcc_equals(info.dataType, "sp78") && !fourcc_equals(info.dataType, "flt ")) {
            continue;
        }

        SMCVal_t val = {0};
        if (smc_read_bytes(key, &info, &val) != KERN_SUCCESS) continue;

        double temp = 0.0;
        if (fourcc_equals(info.dataType, "sp78") && info.dataSize >= 2) {
            temp = decode_sp78((const unsigned char *)val.bytes);
        } else if (fourcc_equals(info.dataType, "flt ") && info.dataSize >= 4) {
            temp = decode_flt((const unsigned char *)val.bytes);
        } else {
            continue;
        }

        if (temp < -10.0 || temp > 130.0) continue;

        char type_str[5];
        key_to_str(info.dataType, type_str);

        printf("%s  type=%s  size=%u  value=%.2f\n", key_str, type_str, info.dataSize, temp);
        printed++;
        if (printed >= max_print) break;
    }

    smc_close();
    return 0;
}
