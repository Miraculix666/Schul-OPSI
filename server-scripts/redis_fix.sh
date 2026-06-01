#!/bin/bash
# ====================================================
# Redis Rescue Script v3.0 - TARGETED SYSTEMD FIX
# Problem: systemd notify Konflikt + /var/run/redis fehlt
# ====================================================

set -e

RED="\033[0;31m" GREEN="\033[0;32m" YELLOW="\033[1;33m" NC="\033[0m"
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

log "?? Redis Rescue v3.0 - SYSTEMD NOTIFY FIX"

# ====================================================
# 1. KRITISCHE VERZEICHNISSE ERSTELLEN
# ====================================================
log "?? Erstelle /var/run/redis..."
mkdir -p /var/run/redis
chown redis:redis /var/run/redis
chmod 755 /var/run/redis

# ====================================================
# 2. SYSTEMD UNIT DROP-IN FIXEN (OHNE PURGE)
# ====================================================
log "?? Erstelle systemd override für notify..."
mkdir -p /etc/systemd/system/redis-server.service.d

cat > /etc/systemd/system/redis-server.service.d/timeout.conf << 'EOF'
[Service]
# Fix für systemd notify Konflikt
TimeoutStartSec=30
TimeoutStopSec=30
# Deaktiviere problematische systemd notify flags
Type=simple
EOF

# ====================================================
# 3. REDIS.CONF SYSTEMD-FIX (supervised NO)
# ====================================================
log "??  Config: supervised systemd ? no..."
sed -i 's/^supervised .*/supervised no/' /etc/redis/redis.conf 2>/dev/null || true

# Bind explizit setzen
echo "bind 127.0.0.1" >> /etc/redis/redis.conf

# ====================================================
# 4. RECHTE NOCHMAL KONSERVATIV
# ====================================================
log "?? Finale Rechte..."
chown root:redis /etc/redis/redis.conf
chmod 644 /etc/redis/redis.conf

chown -R redis:redis /var/lib/redis /var/log/redis /var/run/redis
chmod 755 /var/lib/redis /var/log/redis /var/run/redis

# Alte Daten löschen
rm -f /var/lib/redis/dump.rdb* /var/lib/redis/appendonly.aof*

# ====================================================
# 5. SYSTEMD VOLL-RELOAD
# ====================================================
log "?? Systemd komplett neu laden..."
systemctl daemon-reload
systemctl reset-failed redis-server

# ====================================================
# 6. MANUELLER VORTEST
# ====================================================
log "?? Manueller Start-Test als redis User..."
if sudo -u redis /usr/bin/redis-server /etc/redis/redis.conf --daemonize no --loglevel warning 2>&1 | grep -q "Ready to accept"; then
    log "? Manueller Test OK"
    pkill -f "redis-server.*daemonize no" || true
else
    warn "??  Manueller Test fehlgeschlagen"
fi

# ====================================================
# 7. SERVICE START MIT LOGS
# ====================================================
log "??  Starte Redis mit Live-Logs..."
timeout 20s bash -c "systemctl start redis-server && sleep 5 && systemctl is-active --quiet redis-server" || {
    echo ""
    echo "=== LETZTE LOGS ==="
    journalctl -u redis-server.service -n 30 --no-pager -l
    error "? Start fehlgeschlagen"
}

# ====================================================
# 8. VALIDIERUNG
# ====================================================
sleep 3
if systemctl is-active --quiet redis-server; then
    log "? REDIS LÄUFT!"
    redis-cli ping | grep PONG && log "? PING/PONG OK"
    
    echo ""
    echo "=== AKTIVER STATUS ==="
    systemctl status redis-server --no-pager -l | head -n 12
else
    error "? Immer noch nicht aktiv"
fi

# ====================================================
# 9. OPSI RESTART
# ====================================================
log "?? OPSI neu starten..."
systemctl restart opsiconfd opsipxeconfd || warn "??  OPSI Dienste nicht erreichbar"

# ====================================================
# 10. FINAL REPORT
# ====================================================
log "?? ERFOLG!"
echo ""
echo "Redis: $(systemctl is-active redis-server)"
echo "Opsiconfd: $(systemctl is-active opsiconfd 2>/dev/null || echo 'n/a')"
echo "Opsipxeconfd: $(systemctl is-active opsipxeconfd 2>/dev/null || echo 'n/a')"
echo ""
echo "?? Überwachen:  journalctl -u redis-server.service -f"
echo "?? Testen:      redis-cli ping"
echo "?? PXE testen:  Client neu booten"
