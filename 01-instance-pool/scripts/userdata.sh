#!/bin/bash
# ================================================================================
# userdata.sh
# Runs once on first boot via cloud-init. Installs Apache, fetches instance
# metadata via OCI IMDSv2, and writes an OCI-themed HTML page to the web root.
# ================================================================================

# Redirect all stdout and stderr to the log file for post-boot debugging
exec > /root/userdata.log 2>&1

# OCI fires cloud-init before internet routing is fully established — wait
# for actual HTTP connectivity before running dnf
echo "NOTE: Waiting for network connectivity..."
until curl -4 -sf --max-time 5 http://yum.oracle.com/ > /dev/null 2>&1; do
  echo "NOTE: Network not ready, retrying in 5 seconds..."
  sleep 5
done
echo "NOTE: Network ready."

echo "NOTE: Installing httpd and jq..."
# Retry dnf up to 5 minutes — repo endpoints can be transiently unreachable
# at early boot even after the basic connectivity check passes
for attempt in $(seq 1 10); do
  dnf install -y httpd jq && break
  if [ "${attempt}" -eq 10 ]; then
    echo "ERROR: dnf failed after 10 attempts, giving up."
    exit 1
  fi
  echo "NOTE: dnf attempt ${attempt} failed, retrying in 30s..."
  sleep 30
done

# ------------------------------------------------------------------------------
# Fetch Instance Metadata
# OCI IMDSv2 requires the Authorization header.
# ------------------------------------------------------------------------------

METADATA=$(curl -sf -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/)

IP=$(curl -sf -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].privateIp')

# OCIDs are ~100 chars — show last 12 chars of the unique suffix only
INSTANCE_ID="...$(echo "$METADATA" | jq -r '.id | split(".") | last | .[-12:]')"

AD=$(echo "$METADATA" | jq -r '.availabilityDomain')

SHAPE=$(echo "$METADATA" | jq -r '.shape')

# ------------------------------------------------------------------------------
# Write HTML Page
# ------------------------------------------------------------------------------

cat > /var/www/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OCI Auto Scaling</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #FFFFFF;
      font-family: -apple-system, 'Segoe UI', Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    .card {
      background: #1A2535;
      border-radius: 6px;
      border-top: 4px solid #C74634;
      padding: 36px 32px;
      width: min(480px, 100%);
      box-shadow: 0 12px 40px rgba(0,0,0,0.5);
    }
    .badge-row {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }
    .oci-badge {
      background: #C74634;
      color: #FFFFFF;
      font-size: 13px;
      font-weight: 800;
      padding: 4px 10px;
      border-radius: 2px;
      letter-spacing: 1px;
    }
    .badge-label {
      color: #8A9BB0;
      font-size: 13px;
      letter-spacing: 1px;
      text-transform: uppercase;
    }
    .title {
      color: #FFFFFF;
      font-size: 22px;
      font-weight: 300;
      margin-bottom: 28px;
    }
    table { width: 100%; border-collapse: collapse; }
    tr { border-bottom: 1px solid #263040; }
    tr:last-child { border-bottom: none; }
    td { padding: 14px 0; vertical-align: top; }
    .label {
      color: #8A9BB0;
      font-size: 14px;
      letter-spacing: 0.8px;
      text-transform: uppercase;
      width: 45%;
    }
    .value {
      color: #FFFFFF;
      font-family: 'Courier New', Courier, monospace;
      font-size: 16px;
      font-weight: 600;
      text-align: right;
      word-break: break-all;
    }
    @media (max-width: 420px) {
      td { display: block; }
      .label { width: 100%; padding-bottom: 4px; }
      .value { text-align: left; padding-top: 0; font-size: 18px; }
    }
    .footer {
      margin-top: 28px;
      padding-top: 18px;
      border-top: 1px solid #263040;
      text-align: center;
      color: #4A5A6A;
      font-size: 12px;
      letter-spacing: 1.5px;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge-row">
      <span class="oci-badge">OCI</span>
      <span class="badge-label">Instance Pool Auto Scaling</span>
    </div>
    <div class="title">&#x2601; Instance Details</div>
    <table>
      <tr>
        <td class="label">Private IP</td>
        <td class="value">$IP</td>
      </tr>
      <tr>
        <td class="label">Instance ID</td>
        <td class="value">$INSTANCE_ID</td>
      </tr>
      <tr>
        <td class="label">Availability Domain</td>
        <td class="value">$AD</td>
      </tr>
      <tr>
        <td class="label">Shape</td>
        <td class="value">$SHAPE</td>
      </tr>
    </table>
    <div class="footer">Oracle Cloud Infrastructure &bull; Instance Pool</div>
  </div>
</body>
</html>
HTMLEOF

# Plain-text endpoint for scripted health checks — avoids piping HTML through
# validate.sh and polluting terminal output
echo "$IP" > /var/www/html/plain

echo "NOTE: Enabling and starting httpd..."
systemctl enable httpd
systemctl start httpd

# Oracle Linux 9 ships with firewalld active — open port 80 so the load
# balancer health checks and traffic can reach httpd
echo "NOTE: Opening port 80 in firewalld..."
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "NOTE: Done."
