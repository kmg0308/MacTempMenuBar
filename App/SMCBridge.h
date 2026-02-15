#ifndef SMCBridge_h
#define SMCBridge_h

#ifdef __cplusplus
extern "C" {
#endif

// Initialize SMC connection and cache temperature-capable keys.
// Returns 0 on success.
int smc_temp_init(void);

// Reads the maximum temperature (Celsius) among cached temperature keys.
// - out_temp_c: required
// - out_key: optional (may be NULL). Must point to a buffer of at least 5 bytes.
// Returns 0 on success.
int smc_temp_read_max(double *out_temp_c, char out_key[5]);

// Close SMC connection (safe to call multiple times).
void smc_temp_close(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* SMCBridge_h */
