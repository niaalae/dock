# Local (Non-Docker) Setup Guide

This guide explains how to set up and run the application without Docker, using the new scripts provided.

## Prerequisites
- Linux machine (or WSL)
- `curl`, `jq`, and `tor` installed (`sudo apt install curl jq tor`)

## Setup Steps

1. **Run the Local Setup Script**

   ```bash
   ./local_setup.sh <WALLET> <CPU_PCT> <WORKER_NAME>
   ```
   - Example:
     ```bash
     ./local_setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F 100 humaib4
     ```
   - This will download the miner, generate `config/preferences.json`, and set up logging.

2. **Start Tor Locally**

   ```bash
   bash scripts/local_network.sh
   ```
   - This will start Tor in the background using a local config.

3. **Start the Local Scheduler**

   ```bash
   bash scripts/local_scheduler.sh
   ```
   - This script will monitor and restart Tor and the miner as needed.
   - Output from the miner is logged to `xmrig_out.log`.

## Notes
- Docker is no longer required for this setup.
- The application and Tor will run directly on your machine.
- To stop, kill the `local_scheduler.sh` process (which will also stop the miner and Tor).

---

**For more details, see the included report in the repository.**
