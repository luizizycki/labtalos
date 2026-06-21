#!/bin/bash
set -euo pipefail

# ============================================================
# oci-arm-retry.sh — Tenta criar instância ARM Ampere A1
# alternando entre regiões até conseguir capacidade
#
# Uso: ./oci-arm-retry.sh              # roda uma vez
#      ./oci-arm-retry.sh --loop        # fica tentando até conseguir
# ============================================================

LOGFILE="/var/log/oci-arm-retry.log"
MAX_ATTEMPTS_PER_REGION=10
SLEEP_BETWEEN=60            # segundos entre tentativas na mesma região
SLEEP_BETWEEN_REGIONS=30    # segundos ao trocar de região
LOOP="${2:-false}"

# === PARÂMETROS DA INSTÂNCIA (extraídos da AMD atual) ===
COMPARTMENT="ocid1.tenancy.oc1..aaaaaaaauwduyjyykj5gulaoa2orb7hulqh3exordorei6y4oee7xyfp3wga"
SUBNET="ocid1.subnet.oc1.sa-vinhedo-1.aaaaaaaa5kpil6azj7fymp5iwa2zorwmnyojvfxkixdtwti7x3xurgmatfwa"
IMAGE="ocid1.image.oc1.sa-vinhedo-1.aaaaaaaavtohwn7mzplxp3smvjlvq66mue6zfkz3mh4xbhopkdv36bjyo4ma"
AD_NAME="VBEB:SA-VINHEDO-1-AD-1"
SHAPE="VM.Standard.A1.Flex"
OCPUS=4
MEMORY_GB=24
SSH_KEY="$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo 'ssh-rsa ...')"
DISPLAY_NAME="vpn-arm"
HOSTNAME_LABEL="vpn"

# === REGIÕES (ordenadas por proximidade de SC) ===
# Primeiro tenta a atual, depois as demais
declare -A REGIONS
REGIONS=(
  ["sa-vinhedo-1"]="VBEB:SA-VINHEDO-1-AD-1"
)
# Se quiser adicionar mais regiões, descomente e assine no console OCI:
# ["sa-saopaulo-1"]="IqE:SA-SAOPAULO-1-AD-1"
# ["us-ashburn-1"]="epb:US-ASHBURN-AD-1"
# ["us-phoenix-1"]="nHk:US-PHOENIX-AD-1"
# ["eu-frankfurt-1"]="UNS:EU-FRANKFURT-1-AD-1"
# ["uk-london-1"]="UNS:UK-LONDON-1-AD-1"
# ["ap-sydney-1"]="UNS:AP-SYDNEY-1-AD-1"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

try_region() {
    local region="$1"
    local ad="$2"
    local attempt=0

    log "► Região: $region | AD: $ad"
    oci iam region-subscription list --region "$region" 2>/dev/null | grep -q "$region" || {
        log "  Região $region não assinada. Tentando assinar..."
        oci iam region-subscription add --region-name "$region" 2>/dev/null || true
        sleep 10
    }

    while [ "$attempt" -lt "$MAX_ATTEMPTS_PER_REGION" ]; do
        attempt=$((attempt + 1))
        log "  Tentativa $attempt/$MAX_ATTEMPTS_PER_REGION..."

        local output
        output=$(oci compute instance launch \
            --compartment-id "$COMPARTMENT" \
            --region "$region" \
            --availability-domain "$ad" \
            --display-name "$DISPLAY_NAME" \
            --shape "$SHAPE" \
            --shape-config "{\"ocpus\":$OCPUS,\"memory-in-gbs\":$MEMORY_GB}" \
            --subnet-id "$SUBNET" \
            --image-id "$IMAGE" \
            --ssh-authorized-keys-file <(echo "$SSH_KEY") \
            --hostname-label "$HOSTNAME_LABEL" \
            --assign-public-ip true \
            --wait-for-state RUNNING \
            2>&1) || true

        if echo "$output" | grep -q "Out of capacity\|OutOfCapacity\|InsufficientCapacity\|LimitExceeded"; then
            log "  ⚠ Sem capacidade na $region. Tentativa $attempt."
            sleep "$SLEEP_BETWEEN"
        elif echo "$output" | grep -q "RUNNING\|lifecycle-state\": \"RUNNING"; then
            local instance_id
            instance_id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "unknown")
            log "  ✅ INSTÂNCIA CRIADA! ID: $instance_id"
            post_provision "$instance_id" "$region"
            return 0
        else
            log "  ❌ Erro inesperado: $(echo "$output" | head -5)"
            log "  Tentando novamente..."
            sleep "$SLEEP_BETWEEN"
        fi
    done

    log "  Esgotou tentativas na $region."
    return 1
}

post_provision() {
    local instance_id="$1"
    local region="$2"

    log "► Pós-provisionamento..."

    local public_ip
    sleep 30
    for i in $(seq 1 10); do
        public_ip=$(oci compute instance list-vnics \
            --instance-id "$instance_id" \
            --region "$region" 2>/dev/null | python3 -c \
            "import json,sys;d=json.load(sys.stdin);print(d['data'][0]['public-ip'])" 2>/dev/null) || true
        [ -n "$public_ip" ] && [ "$public_ip" != "null" ] && break
        sleep 10
    done

    if [ -z "$public_ip" ] || [ "$public_ip" = "null" ]; then
        log "  ❌ Não consegui obter o IP público."
        return 1
    fi

    log "  IP Público: $public_ip"

    log "  Script de setup manual necessário:"
    log "  ------------------------------------"
    log "  1. ssh rocky@$public_ip"
    log "  2. sudo apt install -y haproxy wireguard"
    log "  3. Copiar configs de oci/haproxy.cfg e oci/wg0-oci-server.conf"
    log "  4. sudo systemctl enable --now haproxy wg-quick@wg0"
    log "  5. Ajustar WG peer endpoint no LXC para $public_ip:51820"
    log "  6. Atualizar DNS Cloudflare A record -> $public_ip"
    log "  7. Destruir AMD antiga: oci compute instance terminate"
    log ""
    log "  📄 Configs salvas em: oci/haproxy.cfg oci/wg0-oci-server.conf"
    log "  🔑 WG PSK (LXC): 1ptxvlOESeBQg7CAJCQs/OtqVNKZtRnSqP9mSepgFX4="
}

# ============================================================
# MAIN
# ============================================================
log "=== oci-arm-retry.sh iniciado ==="

if [ "${1:-}" = "--loop" ]; then
    while true; do
        for region in "${!REGIONS[@]}"; do
            if try_region "$region" "${REGIONS[$region]}"; then
                log "=== FINALIZADO COM SUCESSO ==="
                exit 0
            fi
            sleep "$SLEEP_BETWEEN_REGIONS"
        done
        log "--- Ciclo completo, nenhuma região teve capacidade. ---"
        log "--- Próxima tentativa em 5 minutos ---"
        sleep 300
    done
else
    for region in "${!REGIONS[@]}"; do
        if try_region "$region" "${REGIONS[$region]}"; then
            log "=== FINALIZADO COM SUCESSO ==="
            exit 0
        fi
        sleep "$SLEEP_BETWEEN_REGIONS"
    done
    log "=== Nenhuma região conseguiu capacidade ==="
    exit 1
fi
