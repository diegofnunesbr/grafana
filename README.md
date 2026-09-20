# grafana

Instalação do **Grafana** via chart oficial (`grafana/grafana`), usando uma
Application multi-source do Argo CD: o chart vem direto do repositório
Helm da Grafana, e os `values.yaml` (datasource do Mimir, persistência,
etc.) vêm deste repositório.

## Pré-requisitos

- `Kubernetes` instalado
- `kubectl` e `kubeseal` instalados
- ArgoCD instalado (ver repositório `argocd`)
- `Sealed Secrets` instalado
- Repositório `mimir` já instalado (o datasource padrão aponta pra ele)

## Estrutura do repositório

```text
grafana/
├── applications/
│   └── argocd.grafana.yaml     # Application multi-source do Argo CD
├── values.yaml                 # values do chart oficial grafana/grafana
└── README.md
```

## Gerar o SealedSecret grafana-admin-secret

```bash
printf '%s' 'SUA_SENHA_AQUI' > /tmp/admin-password
kubectl create secret generic grafana-admin-secret -n observability \
  --from-literal=admin-user=admin \
  --from-file=admin-password=/tmp/admin-password \
  --dry-run=client -o yaml > unsealed.secret.yaml
kubeseal --scope cluster-wide --format yaml < unsealed.secret.yaml > sealed.secret.yaml
rm -f /tmp/admin-password unsealed.secret.yaml
kubectl apply -f sealed.secret.yaml
```

O namespace `observability` só existe depois que o Mimir (ou essa própria
Application, via `CreateNamespace=true`) for aplicado - se rodar antes,
crie o namespace manualmente primeiro.

## Instalar o Grafana

```bash
git clone https://github.com/diegofnunesbr/grafana.git
cd grafana
kubectl apply -f applications/argocd.grafana.yaml
```

## Acessar

O Service é `NodePort` fixo na porta `30300`, igual Mimir (`30900`) e
Rundeck (`30440`) - acesse direto em:

```text
http://<ip-do-node-k0s>:30300
```

Login com o usuário/senha do SealedSecret gerado acima. Se preferir não
expor via NodePort, dá pra usar port-forward em vez disso:

```bash
kubectl -n observability port-forward svc/grafana 3000:80
```

## Verificar

```bash
kubectl -n observability port-forward svc/grafana 13000:80 &
curl -s -u admin:SUA_SENHA http://localhost:13000/api/health
curl -s -u admin:SUA_SENHA http://localhost:13000/api/datasources
```

O `/api/health` deve responder `"database":"ok"`, e `/api/datasources`
deve listar o datasource `Mimir` com `"isDefault":true`.

## Remover o Grafana

```bash
cd grafana
kubectl delete -f applications/argocd.grafana.yaml
```
