#!/bin/bash
set -ex

########################################
# Detect target platform
########################################
: "${TARGETPLATFORM:=$(uname -m)}"

case "$TARGETPLATFORM" in
  linux/amd64|x86_64) DNSPROXY_ARCH="amd64" ;;
  linux/arm64|aarch64) DNSPROXY_ARCH="arm64" ;;
  linux/arm/v7|armv7l) DNSPROXY_ARCH="arm7" ;;
  linux/arm/v6|armv6l) DNSPROXY_ARCH="arm6" ;;
  linux/386|i386) DNSPROXY_ARCH="386" ;;
  *)
    echo "Unsupported platform: $TARGETPLATFORM"
    exit 1
    ;;
esac

echo "Detected architecture: $DNSPROXY_ARCH"

########################################
# Install latest stable dnsproxy
########################################
echo "Fetching latest stable dnsproxy release..."
DNSPROXY_VERSION=$(curl -s --max-time 10 https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest \
  | grep -Po '"tag_name": *"\K[^"]+' || true)

# Fall back to a known-good version if the API is unavailable (rate-limited, network issue, etc.)
if [ -z "$DNSPROXY_VERSION" ]; then
    DNSPROXY_VERSION="v0.81.4"
    echo "GitHub API unavailable, using fallback version: $DNSPROXY_VERSION"
else
    echo "Latest stable dnsproxy release: $DNSPROXY_VERSION"
fi

DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${DNSPROXY_VERSION}/dnsproxy-linux-${DNSPROXY_ARCH}-${DNSPROXY_VERSION}.tar.gz"
echo "Downloading $DNSPROXY_URL"

wget -O /tmp/dnsproxy.tar.gz "$DNSPROXY_URL"

if [ ! -f "/tmp/dnsproxy.tar.gz" ]; then
    echo "ERROR: dnsproxy tarball missing!"
    exit 1
fi

FILE_SIZE=$(stat -c%s "/tmp/dnsproxy.tar.gz" 2>/dev/null || stat -f%z "/tmp/dnsproxy.tar.gz" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 100000 ]; then
    echo "ERROR: Downloaded file is too small ($FILE_SIZE bytes), likely an error page"
    head -n 20 /tmp/dnsproxy.tar.gz
    exit 1
fi

if ! tar -tzf /tmp/dnsproxy.tar.gz > /dev/null 2>&1; then
    echo "ERROR: Downloaded file is not a valid tar.gz archive"
    exit 1
fi

echo "Extracting dnsproxy..."
tar -xzf /tmp/dnsproxy.tar.gz -C /tmp

DNSPROXY_BIN=$(find /tmp -name "dnsproxy" -type f | head -n 1)
if [ -z "$DNSPROXY_BIN" ]; then
    echo "ERROR: dnsproxy binary not found in archive"
    exit 1
fi

cp "$DNSPROXY_BIN" /usr/local/bin/dnsproxy
chmod +x /usr/local/bin/dnsproxy
rm -rf /tmp/dnsproxy.tar.gz /tmp/linux-*
echo "dnsproxy installed successfully"

########################################
# Store default config templates
# (copied to mounted volumes on first container start if missing)
########################################
mkdir -p /usr/local/share/dnsproxy-defaults
if [ -f /temp/dnsproxy.yml ]; then
    cp /temp/dnsproxy.yml /usr/local/share/dnsproxy-defaults/dnsproxy.yml
else
    cat << 'EOF' > /usr/local/share/dnsproxy-defaults/dnsproxy.yml
listen-addrs:
  - 127.0.0.1
listen-ports:
  - 5054
upstream:
  - tls://1.1.1.1
  - tls://1.0.0.1
  - https://cloudflare-dns.com/dns-query
cache: true
timeout: 10s
EOF
fi

########################################
# _start-dnsproxy.sh
# Injected into start.sh after ftl_config (same injection point as
# pihole-updatelists "config" hook). Volumes are guaranteed mounted at
# this point. Configures /config/dnsproxy.yml via three-tier priority:
#   1. DNSPROXY_UPSTREAM env var — generates dnsproxy.yml from env vars each start
#   2. /config/dnsproxy.yml already exists — use as-is (file-based config)
#   3. Neither — auto-copy from baked-in defaults (Cloudflare Default DoT/DoH)
# Then starts dnsproxy in background on 127.0.0.1:5054.
########################################
cat << 'EOF' > /usr/local/bin/_start-dnsproxy.sh
#!/bin/bash
if [ -n "${DNSPROXY_UPSTREAM}" ]; then
    echo "  [i] DNSPROXY_UPSTREAM env var set — generating /config/dnsproxy.yml"
    mkdir -p /config
    {
        echo "listen-addrs:"
        echo "  - 127.0.0.1"
        echo "listen-ports:"
        echo "  - 5054"
        echo "upstream:"
        for _url in ${DNSPROXY_UPSTREAM}; do
            echo "  - ${_url}"
        done
        echo "bootstrap:"
        _bs="${DNSPROXY_BOOTSTRAP:-1.1.1.1 1.0.0.1 9.9.9.9}"
        for _ip in ${_bs}; do
            echo "  - ${_ip}"
        done
        echo "cache: true"
        echo "timeout: 10s"
    } > /config/dnsproxy.yml
elif [ ! -f /config/dnsproxy.yml ] && [ -f /usr/local/share/dnsproxy-defaults/dnsproxy.yml ]; then
    echo "  [i] Initializing /config/dnsproxy.yml from defaults"
    mkdir -p /config
    cp /usr/local/share/dnsproxy-defaults/dnsproxy.yml /config/dnsproxy.yml
fi
echo "  [i] Starting dnsproxy (DoT/DoH) on 127.0.0.1:5054"
/usr/local/bin/dnsproxy --config-path=/config/dnsproxy.yml >/var/log/dnsproxy.log 2>&1 &
EOF
chmod +x /usr/local/bin/_start-dnsproxy.sh

########################################
# Inject into Pi-hole's startup scripts
# Pattern mirrors jacklul/pihole-updatelists docker install exactly:
#   start.sh injections use sed with \s\+ patterns (BusyBox sed compatible)
#
# Our injections run at BUILD TIME on the original scripts, then
# pihole-updatelists installer runs AFTER us and adds its own hooks.
# Final order in start.sh:
#   ftl_config
#   bash /usr/local/bin/_start-dnsproxy.sh       <- our inject (after ftl_config)
#   pihole-updatelists.sh config                 <- pihole-updatelists inject
#   install_additional_packages
#   pihole-updatelists.sh cron                   <- pihole-updatelists inject
#   start_cron                                   <- loads /crontab.txt, starts crond
#
# Final order in bash_functions.sh (inside migrate_gravity, first start only):
#   pihole -g
#   pihole-updatelists.sh run                   <- pihole-updatelists inject
########################################

# start.sh: start dnsproxy after ftl_config (volumes mounted, config readable)
sed '/^\s\+ftl_config/a bash /usr/local/bin/_start-dnsproxy.sh' -i /usr/bin/start.sh

# Verify injection succeeded
grep -q '_start-dnsproxy.sh' /usr/bin/start.sh || { echo "ERROR: _start-dnsproxy.sh injection failed"; exit 1; }

echo "dnsproxy installation complete"
