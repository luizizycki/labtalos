# Lab Talos

Cluster Kubernetes Talos + GitOps via ArgoCD.

## Bootstrap

Única intervenção manual. Executar na ordem após `terraform apply`:

```bash
# 1 — Aguardar nodes prontos
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# 2 — Aplicar CRDs do Gateway API
kubectl apply --server-side -f crds/gateway-api/

# 3 — Instalar ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --values helm-values/argocd.yaml

# 4 — ArgoCD assume o controle
kubectl apply -f apps/bootstrap-app.yaml
```

## GitOps Flow

Toda mudança é feita via git push para `origin/main`:

```
git add . && git commit -m "..." && git push origin main
```

ArgoCD detecta o drift e sincroniza automaticamente (automated sync + selfHeal + prune).

## Versões

| Componente | Versão |
|---|---|
| Talos | v1.13.2 |
| Kubernetes | v1.34.1 |
| Cilium | v1.17.2 |
| ArgoCD | v3.4.3 (chart: argo-cd 9.5.17) |
| Gateway API | v1.2.x |
