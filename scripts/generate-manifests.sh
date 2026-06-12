#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CILIUM_VERSION="${CILIUM_VERSION:-1.17.2}"

echo "==> Garantindo repositório Helm do Cilium..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium 2>/dev/null || true

echo "==> Gerando generated/cilium.yaml (Cilium $CILIUM_VERSION)..."
helm template cilium cilium/cilium \
  --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --values "$DIR/helm-values/cilium.yaml" \
  > "$DIR/generated/cilium.yaml"

echo "==> Verificando se há private keys no arquivo gerado..."
if grep -q "BEGIN.*PRIVATE KEY" "$DIR/generated/cilium.yaml"; then
  echo "ERRO: private keys encontradas no generated/cilium.yaml!"
  echo "Adicione 'hubble.tls.auto.method: cronJob' ao helm-values/cilium.yaml e regenere."
  exit 1
fi

echo "==> OK: generated/cilium.yaml gerado sem secrets."
echo "    Tamanho: $(wc -c < "$DIR/generated/cilium.yaml") bytes"
echo "    Recursos: $(grep -c '^kind:' "$DIR/generated/cilium.yaml")"
echo ""
echo "Caso queira gerar para ArgoCD também (futuro):"
echo "  helm template argocd argo/argo-cd \\"
echo "    --version 9.5.17 \\"
echo "    --namespace argocd --create-namespace \\"
echo "    --values helm-values/argocd.yaml > generated/argocd.yaml"
