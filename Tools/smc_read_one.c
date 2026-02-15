// Read a single SMC key and print raw bytes + decoded values.
// Build:
//   clang -O2 -Wall -Wextra -framework IOKit -framework CoreFoundation -o smc_read_one smc_read_one.c
// Run:
//   ./smc_read_one TC0P

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

#define KERNEL_INDEX_SMC 2

#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

static io_connect_t g_conn = IO_OBJECT_NULL;

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

    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    if (service == IO_OBJECT_NULL) {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    }
    if (service == IO_OBJECT_NULL) {
        fprintf(stderr, "SMC service not found\n");
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

static double decode_sp78(const unsigned char *b) {
    int16_t raw = (int16_t)((b[0] << 8) | b[1]);
    return (double)raw / 256.0;
}

static double decode_flt_be(const unsigned char *b) {
    uint32_t u = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
    float f = 0;
    memcpy(&f, &u, sizeof(f));
    return (double)f;
}

static double decode_flt_le(const unsigned char *b) {
    uint32_t u = ((uint32_t)b[3] << 24) | ((uint32_t)b[2] << 16) | ((uint32_t)b[1] << 8) | (uint32_t)b[0];
    float f = 0;
    memcpy(&f, &u, sizeof(f));
    return (double)f;
}

int main(int argc, char **argv) {
    const char *k = (argc >= 2) ? argv[1] : "TC0P";
    if (strlen(k) != 4) {
        fprintf(stderr, "Key must be 4 characters\n");
        return 1;
    }

    if (smc_open() != 0) return 1;

    uint32_t key = str_to_key(k);
    SMCKeyData_keyInfo_t info = {0};
    kern_return_t kr = smc_read_key_info(key, &info);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "smc_read_key_info failed: 0x%x\n", kr);
        smc_close();
        return 1;
    }

    SMCVal_t val = {0};
    kr = smc_read_bytes(key, &info, &val);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "smc_read_bytes failed: 0x%x\n", kr);
        smc_close();
        return 1;
    }

    char type_str[5];
    key_to_str(info.dataType, type_str);

    printf("Key: %s\n", k);
    printf("Type: %s\n", type_str);
    printf("Size: %u\n", info.dataSize);

    printf("Bytes:");
    for (uint32_t i = 0; i < info.dataSize && i < SMC_MAX_BYTES; i++) {
        printf(" %02X", (unsigned char)val.bytes[i]);
    }
    printf("\n");

    if (strncmp(type_str, "sp78", 4) == 0 && info.dataSize >= 2) {
        printf("Decoded(sp78): %.4f\n", decode_sp78((const unsigned char *)val.bytes));
    } else if (strncmp(type_str, "flt ", 4) == 0 && info.dataSize >= 4) {
        printf("Decoded(flt, big-endian): %.6f\n", decode_flt_be((const unsigned char *)val.bytes));
        printf("Decoded(flt, little-endian): %.6f\n", decode_flt_le((const unsigned char *)val.bytes));
    } else if (strncmp(type_str, "ui32", 4) == 0 && info.dataSize >= 4) {
        const unsigned char *b = (const unsigned char *)val.bytes;
        uint32_t be = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
        uint32_t le = ((uint32_t)b[3] << 24) | ((uint32_t)b[2] << 16) | ((uint32_t)b[1] << 8) | (uint32_t)b[0];
        printf("Decoded(ui32, big-endian): %u (0x%08X)\n", be, be);
        printf("Decoded(ui32, little-endian): %u (0x%08X)\n", le, le);
    } else {
        printf("No decoder for this type\n");
    }

    smc_close();
    return 0;
}
