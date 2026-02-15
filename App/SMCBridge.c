#include "SMCBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
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

#define SMC_TEMP_KEY_CAPACITY 512
#define SMC_HOT_KEY_CAPACITY 24
#define SMC_HOT_REFRESH_INTERVAL_SEC 30.0

typedef struct {
    uint32_t key;
    uint32_t dataSize;
    uint32_t dataType;
    char keyStr[5];
} SMCTempKey;

static io_connect_t g_conn = IO_OBJECT_NULL;
static int g_initialized = 0;
static SMCTempKey g_temp_keys[SMC_TEMP_KEY_CAPACITY];
static uint32_t g_temp_key_count = 0;
static SMCTempKey g_hot_keys[SMC_HOT_KEY_CAPACITY];
static uint32_t g_hot_key_count = 0;
static double g_last_hot_refresh = 0.0;

static uint32_t str_to_key(const char *s) {
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

    // Apple Silicon exposes SMC keys via AppleSMCKeysEndpoint.
    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    if (service == IO_OBJECT_NULL) {
        // Some systems may still expose AppleSMC.
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    }
    if (service == IO_OBJECT_NULL) {
        return 1;
    }

    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);

    if (kr != KERN_SUCCESS) {
        g_conn = IO_OBJECT_NULL;
        return 1;
    }

    return 0;
}

void smc_temp_close(void) {
    if (g_conn != IO_OBJECT_NULL) {
        IOServiceClose(g_conn);
        g_conn = IO_OBJECT_NULL;
    }
    g_initialized = 0;
    g_temp_key_count = 0;
    g_hot_key_count = 0;
    g_last_hot_refresh = 0.0;
}

static int fourcc_equals(uint32_t v, const char *fourcc) {
    return v == str_to_key(fourcc);
}

static int smc_read_u32_key(const char *key_str, uint32_t *out_u32) {
    if (!key_str || strlen(key_str) != 4) return 1;

    uint32_t key = str_to_key(key_str);

    SMCKeyData_keyInfo_t info = {0};
    if (smc_read_key_info(key, &info) != KERN_SUCCESS) return 1;

    SMCVal_t val = {0};
    if (smc_read_bytes(key, &info, &val) != KERN_SUCCESS) return 1;

    if (val.dataSize < 4) return 1;

    // ui32 is big-endian (verified via #KEY).
    const unsigned char *b = (const unsigned char *)val.bytes;
    *out_u32 = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
    return 0;
}

static double decode_sp78(const unsigned char *b) {
    int16_t raw = (int16_t)((b[0] << 8) | b[1]);
    return (double)raw / 256.0;
}

static double decode_flt_le(const unsigned char *b) {
    uint32_t u = ((uint32_t)b[3] << 24) | ((uint32_t)b[2] << 16) | ((uint32_t)b[1] << 8) | (uint32_t)b[0];
    float f = 0;
    memcpy(&f, &u, sizeof(f));
    return (double)f;
}

static int is_temp_plausible(double temp) {
    if (!isfinite(temp)) return 0;
    return (temp >= 10.0 && temp <= 130.0);
}

static int smc_read_temp_for_key(const SMCTempKey *k, double *out_temp) {
    if (!k || !out_temp) return 1;

    SMCKeyData_keyInfo_t info = {0};
    info.dataSize = k->dataSize;
    info.dataType = k->dataType;

    SMCVal_t val = {0};
    if (smc_read_bytes(k->key, &info, &val) != KERN_SUCCESS) {
        return 1;
    }

    double temp = NAN;
    if (fourcc_equals(k->dataType, "sp78") && k->dataSize >= 2) {
        temp = decode_sp78((const unsigned char *)val.bytes);
    } else if (fourcc_equals(k->dataType, "flt ") && k->dataSize >= 4) {
        temp = decode_flt_le((const unsigned char *)val.bytes);
    } else {
        return 1;
    }

    if (!is_temp_plausible(temp)) return 1;

    *out_temp = temp;
    return 0;
}

static int should_exclude_from_hot_set(const char keyStr[5]) {
    // Exclude battery/ambient-like sensors from the \"hot\" set selection.
    // If this excludes everything, we fall back later.
    if (!keyStr) return 0;

    if (keyStr[0] != 'T' && keyStr[0] != 't') return 0;

    // TA.. often looks like ambient; TB.. looks like battery.
    if (keyStr[1] == 'A' || keyStr[1] == 'a') return 1;
    if (keyStr[1] == 'B' || keyStr[1] == 'b') return 1;

    return 0;
}

typedef struct {
    double temp;
    SMCTempKey key;
} SMCTempCandidate;

static void insert_top_candidate(SMCTempCandidate top[SMC_HOT_KEY_CAPACITY], uint32_t *count, SMCTempCandidate cand) {
    uint32_t n = *count;

    if (n < SMC_HOT_KEY_CAPACITY) {
        top[n] = cand;
        n++;
    } else {
        // Already full; quick reject if not hotter than the last element.
        if (cand.temp <= top[n - 1].temp) {
            return;
        }
        top[n - 1] = cand;
    }

    // Bubble into correct position (descending).
    for (uint32_t i = n - 1; i > 0; i--) {
        if (top[i].temp <= top[i - 1].temp) break;
        SMCTempCandidate tmp = top[i];
        top[i] = top[i - 1];
        top[i - 1] = tmp;
    }

    *count = n;
}

static void refresh_hot_keys(int exclude_ambient_battery) {
    SMCTempCandidate top[SMC_HOT_KEY_CAPACITY];
    uint32_t top_count = 0;

    for (uint32_t i = 0; i < g_temp_key_count; i++) {
        const SMCTempKey *k = &g_temp_keys[i];

        if (exclude_ambient_battery && should_exclude_from_hot_set(k->keyStr)) {
            continue;
        }

        double temp = NAN;
        if (smc_read_temp_for_key(k, &temp) != 0) continue;

        SMCTempCandidate cand = {0};
        cand.temp = temp;
        cand.key = *k;
        insert_top_candidate(top, &top_count, cand);
    }

    if (top_count == 0 && exclude_ambient_battery) {
        // Fallback: include everything.
        refresh_hot_keys(0);
        return;
    }

    g_hot_key_count = 0;
    for (uint32_t i = 0; i < top_count; i++) {
        if (g_hot_key_count >= SMC_HOT_KEY_CAPACITY) break;
        g_hot_keys[g_hot_key_count++] = top[i].key;
    }

    g_last_hot_refresh = CFAbsoluteTimeGetCurrent();
}

int smc_temp_init(void) {
    if (g_initialized) return 0;

    if (g_conn == IO_OBJECT_NULL) {
        if (smc_open() != 0) return 1;
    }

    uint32_t key_count = 0;
    if (smc_read_u32_key("#KEY", &key_count) != 0 || key_count == 0) {
        smc_temp_close();
        return 1;
    }

    g_temp_key_count = 0;

    for (uint32_t i = 0; i < key_count; i++) {
        uint32_t key = 0;
        if (smc_get_key_from_index(i, &key) != KERN_SUCCESS) continue;

        char key_str[5];
        key_to_str(key, key_str);

        if (key_str[0] != 'T' && key_str[0] != 't') {
            continue;
        }

        SMCKeyData_keyInfo_t info = {0};
        if (smc_read_key_info(key, &info) != KERN_SUCCESS) continue;

        if (info.dataSize == 0 || info.dataSize > SMC_MAX_BYTES) continue;

        if (!fourcc_equals(info.dataType, "flt ") && !fourcc_equals(info.dataType, "sp78")) {
            continue;
        }

        if (g_temp_key_count >= (uint32_t)(sizeof(g_temp_keys) / sizeof(g_temp_keys[0]))) {
            break;
        }

        SMCTempKey *slot = &g_temp_keys[g_temp_key_count++];
        slot->key = key;
        slot->dataSize = info.dataSize;
        slot->dataType = info.dataType;
        memcpy(slot->keyStr, key_str, 5);
    }

    if (g_temp_key_count == 0) {
        smc_temp_close();
        return 1;
    }

    // Prime the hot set (reduces per-tick work).
    refresh_hot_keys(1);

    g_initialized = 1;
    return 0;
}

static int smc_temp_read_max_internal(double *out_temp_c, char out_key[5]) {
    if (!out_temp_c) return 1;

    if (smc_temp_init() != 0) {
        return 1;
    }

    double best = NAN;
    char best_key[5] = "";

    double now = CFAbsoluteTimeGetCurrent();
    if (g_hot_key_count == 0 || (now - g_last_hot_refresh) >= SMC_HOT_REFRESH_INTERVAL_SEC) {
        refresh_hot_keys(1);
    }

    const SMCTempKey *keys = (g_hot_key_count > 0) ? g_hot_keys : g_temp_keys;
    uint32_t key_count = (g_hot_key_count > 0) ? g_hot_key_count : g_temp_key_count;

    for (uint32_t i = 0; i < key_count; i++) {
        const SMCTempKey *k = &keys[i];

        double temp = NAN;
        if (smc_read_temp_for_key(k, &temp) != 0) continue;

        if (!isfinite(best) || temp > best) {
            best = temp;
            memcpy(best_key, k->keyStr, 5);
        }
    }

    if (!isfinite(best)) {
        return 1;
    }

    *out_temp_c = best;
    if (out_key) {
        memcpy(out_key, best_key, 5);
    }
    return 0;
}

int smc_temp_read_max(double *out_temp_c, char out_key[5]) {
    // Try once, and if it fails (e.g. connection got invalidated), reopen and retry.
    int rc = smc_temp_read_max_internal(out_temp_c, out_key);
    if (rc == 0) return 0;

    smc_temp_close();
    return smc_temp_read_max_internal(out_temp_c, out_key);
}
