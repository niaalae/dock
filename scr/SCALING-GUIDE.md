# System Requirements for Running 30,000 Instances

## Option 1: Single Massive Server (Not Recommended)
**Minimum Specs:**
- CPU: 32-64 vCPUs
- RAM: 512 GB - 1 TB
- Disk: 500 GB SSD
- Network: 10 Gbps
- Cost: $500-2000/month

**Issues:**
- Single point of failure
- GitHub may rate-limit from single IP
- Expensive
- Hard to scale

---

## Option 2: Distributed Fleet (RECOMMENDED)

### Configuration A: Many Small VPS
**40 VPS servers, each running 750 instances:**
- Per VPS: 4 vCPUs, 16 GB RAM, 50 GB Disk
- Cost per VPS: $20-40/month
- Total cost: $800-1600/month
- Providers: Hetzner, OVH, DigitalOcean

### Configuration B: Fewer Larger VPS
**10 VPS servers, each running 3,000 instances:**
- Per VPS: 16 vCPUs, 64 GB RAM, 200 GB Disk
- Cost per VPS: $80-150/month
- Total cost: $800-1500/month
- Providers: AWS, GCP, Azure

---

## Option 3: Optimize to Fit Your Current VPS (2 vCPU / 8GB)

**Your VPS can handle approximately 600-800 instances max**

### Calculation:
- Available RAM: 8 GB = 8,192 MB
- System overhead: ~2 GB = 2,048 MB
- Usable RAM: 6,144 MB
- Per instance: ~8 MB
- **Max instances: 6,144 / 8 = 768 instances**

### To run 30,000 instances:
**You need 30,000 / 768 = ~40 VPS servers** of this size

---

## Setup Instructions

### Step 1: Prepare Token File
Create a file with your GitHub tokens (one per line):
```bash
# tokens.txt
ghp_token1
ghp_token2
ghp_token3
...
```

### Step 2: On Each VPS, Run:
```bash
# Make scripts executable
chmod +x autoS-optimized.sh worker-manager.sh

# Run as root for full optimizations
sudo ./worker-manager.sh 750 tokens.txt
```

### Step 3: Monitor
```bash
# Check running instances
ps aux | grep autoS-optimized | wc -l

# View logs
tail -f /tmp/autoS-*.log

# Check resource usage
htop
```

---

## Cost Optimization Tips

1. **Use cheap providers**: Hetzner (~$5/month for 2vCPU/4GB)
2. **Spot instances**: AWS/GCP spot = 70% cheaper
3. **Stagger instances**: Don't run all 30k at once
4. **Token rotation**: Reuse tokens across VPS
5. **Geographic distribution**: Avoid rate limits

---

## Recommended Setup for 30,000 Instances

**60 Hetzner VPS (CPX21):**
- Each: 3 vCPU, 4 GB RAM, 80 GB Disk
- Each runs: 500 instances
- Cost per VPS: €5.83/month (~$6.50)
- **Total: 60 × $6.50 = $390/month**

This is the most cost-effective solution!
