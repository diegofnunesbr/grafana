#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NODE="${NODE:-diegofnunesbr@192.168.0.4}"
KCTL="kubectl --context=Default"
SEALED=secrets/grafana-admin-secret.sealed.yaml

read -rsp "Nova senha do admin do Grafana: " PW; echo
read -rsp "Confirme a senha: " PW2; echo
[ -n "$PW" ] && [ "$PW" = "$PW2" ] || { echo "Senhas vazias ou diferentes."; exit 1; }

git pull --ff-only

CERT=$(mktemp)
trap 'rm -f "$CERT"' EXIT
ssh "$NODE" "kubeseal --fetch-cert --controller-name sealed-secrets --controller-namespace kube-system" > "$CERT"

cat <<EOF | kubeseal --cert "$CERT" --scope cluster-wide --format yaml > "$SEALED"
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-secret
  namespace: grafana
type: Opaque
data:
  admin-user: $(printf '%s' admin | base64 -w0)
  admin-password: $(printf '%s' "$PW" | base64 -w0)
EOF

git add "$SEALED"
git commit -m "rotate grafana admin password"
git push

printf '%s\n' "$PW" | ssh "$NODE" "$KCTL -n grafana exec -i deploy/grafana -c grafana -- sh -c 'IFS= read -r P; grafana cli admin reset-admin-password \"\$P\"'" >/dev/null 2>&1 \
  || { echo "Falhou o reset no pod do Grafana. O secret já foi pro git; rode de novo ou veja: kubectl -n grafana logs deploy/grafana"; exit 1; }
echo "Pronto. Login: admin + senha nova em https://grafana.diegofnunesbr.com"
