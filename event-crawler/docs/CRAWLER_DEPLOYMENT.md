# Web Crawler Deployment & Automation Guide

This document outlines the best practices for deploying and automating the event crawler on your GCP infrastructure.

## 1. Crawler Automation Strategy

### Production-Ready Automation Architecture

#### A. Scheduling & Orchestration
- **Cron Jobs**: Use systemd timers or traditional cron for simple scheduling
- **Process Monitoring**: Use PM2 or systemd services for process management
- **Dead Letter Queues**: Implement retry logic with exponential backoff
- **Health Checks**: Regular endpoint monitoring and alerting

#### B. Error Handling & Recovery
```typescript
// Enhanced error handling for your main.ts
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 5000;

async function runCrawlerWithRetry(attempt = 1) {
  try {
    await main({ dryRun: false });
    await notifySuccess();
  } catch (error) {
    console.error(`[!] Crawler failed on attempt ${attempt}:`, error);

    if (attempt < MAX_RETRIES) {
      await new Promise(resolve => setTimeout(resolve, RETRY_DELAY_MS * attempt));
      return runCrawlerWithRetry(attempt + 1);
    }

    await notifyFailure(error);
    throw error;
  }
}
```

#### C. Monitoring & Alerting
- **Logs**: Structured JSON logging with log levels
- **Metrics**: Track success rates, processing times, error types
- **Alerts**: Email/Slack notifications for failures
- **Dashboards**: Real-time monitoring of crawler health

### Recommended Tools Stack
- **Process Manager**: PM2 (handles restarts, clustering, monitoring)
- **Scheduling**: PM2 Cron or systemd timers
- **Monitoring**: Winston/Pino for logging + Google Cloud Logging
- **Alerting**: NodeMailer for email alerts or Slack webhooks

## 2. GCP Deployment Strategy

### Using Your Existing Typesense Instance

Your current `main.tf` creates a `e2-medium` instance that can handle both Typesense and the crawler.

#### A. Infrastructure Updates

Add these resources to your `main.tf`:

```hcl
# Additional firewall rule for crawler monitoring
resource "google_compute_firewall" "crawler_monitoring" {
  name    = "allow-crawler-monitoring"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000"] # For crawler dashboard/health checks
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

# Secret for OpenAI API key
resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "openai-api-key"
  replication {
    auto {}
  }
}

# Secret for Firebase credentials
resource "google_secret_manager_secret" "firebase_credentials" {
  secret_id = "firebase-service-account"
  replication {
    auto {}
  }
}

# Grant access to new secrets
resource "google_secret_manager_secret_iam_member" "openai_secret_access" {
  secret_id = google_secret_manager_secret.openai_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.typesense_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "firebase_secret_access" {
  secret_id = google_secret_manager_secret.firebase_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.typesense_sa.email}"
}
```

#### B. Enhanced Startup Script

Update your startup script to include Node.js and crawler setup:

```bash
# Add to your existing metadata_startup_script after Docker installation

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install PM2 globally
npm install -g pm2

# Create crawler directory
mkdir -p /opt/crawler
chown -R ubuntu:ubuntu /opt/crawler

# Create deployment script
cat > /opt/crawler/deploy-crawler.sh << 'EOL'
#!/bin/bash
cd /opt/crawler

# Clone/update repository
if [ -d "tapped" ]; then
    cd tapped && git pull
else
    git clone https://github.com/jonaylor89/tapped.git
    cd tapped
fi

# Install dependencies and build
cd event-crawler
npm ci
npm run build

# Get secrets from Secret Manager
export OPENAI_API_KEY=$(gcloud secrets versions access latest --secret="openai-api-key")
export FIREBASE_CREDENTIALS=$(gcloud secrets versions access latest --secret="firebase-service-account")

# Start with PM2
pm2 start ecosystem.config.js --env production
pm2 save
EOL

chmod +x /opt/crawler/deploy-crawler.sh
chown ubuntu:ubuntu /opt/crawler/deploy-crawler.sh
```

#### C. PM2 Configuration

Create `event-crawler/ecosystem.config.js`:

```javascript
module.exports = {
  apps: [{
    name: 'event-crawler',
    script: './dist/main.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env_production: {
      NODE_ENV: 'production',
      DRY_RUN: 'false'
    },
    cron_restart: '0 2 * * *', // Run daily at 2 AM
    error_file: '/var/log/crawler/error.log',
    out_file: '/var/log/crawler/out.log',
    log_file: '/var/log/crawler/combined.log',
    time: true
  }, {
    name: 'crawler-health-check',
    script: './dist/health-server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
```

### Deployment Workflow

1. **Initial Setup**:
```bash
# SSH into your instance
gcloud compute ssh typesense-instance --zone=us-central1-a

# Run the deployment script
sudo /opt/crawler/deploy-crawler.sh
```

2. **Updates**:
```bash
# Create a simple update script
cd /opt/crawler && ./deploy-crawler.sh
```

3. **Monitoring**:
```bash
# Check crawler status
pm2 status
pm2 logs event-crawler
pm2 monit
```

## 3. Health Monitoring System

### A. Health Check Server

Create `event-crawler/src/health-server.ts`:

```typescript
import express from 'express';
import fs from 'fs';
import path from 'path';

const app = express();
const PORT = process.env.PORT || 3000;

interface CrawlerStatus {
  lastRun: Date | null;
  status: 'running' | 'idle' | 'error';
  lastError: string | null;
  eventsProcessed: number;
}

let crawlerStatus: CrawlerStatus = {
  lastRun: null,
  status: 'idle',
  lastError: null,
  eventsProcessed: 0
};

app.get('/health', (req, res) => {
  const uptime = process.uptime();
  const memoryUsage = process.memoryUsage();

  res.json({
    status: 'healthy',
    uptime,
    memory: memoryUsage,
    crawler: crawlerStatus,
    timestamp: new Date().toISOString()
  });
});

app.get('/logs', (req, res) => {
  try {
    const logPath = '/var/log/crawler/combined.log';
    const logs = fs.readFileSync(logPath, 'utf8').split('\n').slice(-100);
    res.json({ logs });
  } catch (error) {
    res.status(500).json({ error: 'Unable to read logs' });
  }
});

app.listen(PORT, () => {
  console.log(`Health server running on port ${PORT}`);
});

// Export for use in main crawler
export function updateCrawlerStatus(status: Partial<CrawlerStatus>) {
  crawlerStatus = { ...crawlerStatus, ...status };
}
```

### B. Enhanced Main Script with Monitoring

Update your `main.ts`:

```typescript
import { updateCrawlerStatus } from './health-server.js';

// At the beginning of main function
updateCrawlerStatus({ status: 'running', lastRun: new Date() });

// On success
updateCrawlerStatus({
  status: 'idle',
  eventsProcessed: items.length,
  lastError: null
});

// On error
updateCrawlerStatus({
  status: 'error',
  lastError: error.message
});
```

### C. Alerting System

Create `event-crawler/src/alerts.ts`:

```typescript
import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransporter({
  // Configure your email provider
  service: 'gmail',
  auth: {
    user: process.env.ALERT_EMAIL,
    pass: process.env.ALERT_PASSWORD
  }
});

export async function notifyFailure(error: Error) {
  const message = {
    from: process.env.ALERT_EMAIL,
    to: 'your-email@domain.com',
    subject: '🚨 Crawler Failed',
    html: `
      <h2>Event Crawler Failure</h2>
      <p><strong>Time:</strong> ${new Date().toISOString()}</p>
      <p><strong>Error:</strong> ${error.message}</p>
      <pre>${error.stack}</pre>
    `
  };

  await transporter.sendMail(message);
}

export async function notifySuccess() {
  // Optional: Send success notifications less frequently
  console.log('✅ Crawler completed successfully');
}
```

## 4. Residential Proxy Setup

### Option A: Simple Home Proxy (Recommended)

Set up a proxy server at your house using your existing internet connection:

#### 1. Hardware Requirements
- **Raspberry Pi 4** or any always-on computer
- Stable residential internet connection
- Router with port forwarding capabilities

#### 2. Proxy Server Setup

Install **Squid Proxy** on your home device:

```bash
# On Ubuntu/Raspberry Pi OS
sudo apt update && sudo apt install squid apache2-utils

# Create authentication file
sudo htpasswd -c /etc/squid/passwd crawler_user

# Configure Squid
sudo nano /etc/squid/squid.conf
```

**Squid Configuration** (`/etc/squid/squid.conf`):
```bash
# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic children 5
auth_param basic realm Squid proxy-caching web server
auth_param basic credentialsttl 2 hours

# Access control
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Port configuration
http_port 3128

# Logging (optional)
access_log /var/log/squid/access.log squid

# Performance tuning
cache_mem 64 MB
maximum_object_size 10 MB
cache_dir ufs /var/spool/squid 100 16 256
```

#### 3. Router Configuration
- Forward port 3128 to your proxy device
- Set up DDNS (Dynamic DNS) for your home IP
- Consider using a VPN service like Cloudflare Tunnel for better security

#### 4. Secure Access
```bash
# Install Cloudflare Tunnel
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create home-proxy
cloudflared tunnel route dns home-proxy proxy.yourdomain.com

# Configure tunnel
echo "tunnel: your-tunnel-id
credentials-file: /home/pi/.cloudflared/your-tunnel-id.json
ingress:
  - hostname: proxy.yourdomain.com
    service: http://localhost:3128
  - service: http_status:404" > ~/.cloudflared/config.yml

# Run tunnel
cloudflared tunnel run home-proxy
```

#### 5. Integration with Your Crawler

Update your crawler to use the proxy:

```typescript
// In main.ts, uncomment and configure proxy
import { ProxyConfiguration } from 'crawlee';

const proxyConfiguration = new ProxyConfiguration({
  proxyUrls: ['http://crawler_user:password@proxy.yourdomain.com:443']
});

const crawler = new CheerioCrawler({
  proxyConfiguration, // Add this line
  requestHandler: router,
  // ... rest of config
});
```

### Option B: Commercial Residential Proxy Services

For more reliability, consider services like:
- **Bright Data** (formerly Luminati) - Premium but reliable
- **Smartproxy** - Good balance of price/performance
- **ProxyMesh** - Simple and affordable

## 5. Deployment Checklist

### Pre-Deployment
- [ ] Update Terraform configuration with new resources
- [ ] Set up secrets in Google Secret Manager
- [ ] Configure monitoring and alerting
- [ ] Test proxy setup (if using)

### Deployment Steps
- [ ] Apply Terraform changes: `terraform apply`
- [ ] SSH into instance and run deployment script
- [ ] Verify PM2 is running crawler
- [ ] Test health check endpoint
- [ ] Monitor first few runs

### Post-Deployment
- [ ] Set up log rotation
- [ ] Configure backup strategy for crawler data
- [ ] Document operational procedures
- [ ] Set up monitoring dashboards

### Ongoing Maintenance
- [ ] Regular dependency updates
- [ ] Monitor resource usage and scale if needed
- [ ] Review and optimize crawler performance
- [ ] Update venue configurations as needed

## 6. Cost Optimization Tips

### Instance Sizing
- Start with `e2-medium` (shared with Typesense)
- Monitor CPU/Memory usage
- Consider `e2-small` if resource usage is low
- Use preemptible instances for cost savings (with proper restart handling)

### Scheduled Scaling
```hcl
# Add to main.tf for auto-scheduling
resource "google_compute_instance_schedule" "crawler_schedule" {
  name   = "crawler-schedule"
  region = var.region

  vm_start_schedule {
    schedule = "0 1 * * *"  # Start at 1 AM
  }

  vm_stop_schedule {
    schedule = "0 6 * * *"  # Stop at 6 AM
  }
}
```

This setup gives you a robust, monitorable, and maintainable web crawler deployment that can run autonomously while providing the visibility and control you need for maintenance and debugging.
