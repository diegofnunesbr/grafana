# grafana

Instalação do **Grafana** via chart oficial (`grafana/grafana`), usando uma
Application multi-source do Argo CD: o chart vem direto do repositório
Helm da Grafana, e os `values.yaml` (datasource do Mimir, dashboards,
persistência, etc.) vêm deste repositório.

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

## Dashboards

Provisionados via `values.yaml` (chave `dashboards`), não criados na UI -
é o padrão adotado aqui: um dashboard só existe se estiver commitado no
repo, senão some no próximo redeploy do pod. Pra adicionar um novo:

```yaml
dashboards:
  default:
    nome-do-dashboard:
      gnetId: <id do grafana.com/grafana/dashboards>
      revision: <revisão>
      datasource: Mimir
```

Pra um dashboard rascunhado direto na UI: depois de pronto, exporte o JSON
(`Dashboard settings → JSON Model`) e migre pra `dashboards.default.<nome>.json`
no `values.yaml`, em vez de deixar só na UI.

## Troubleshooting: pod trava em `Init:Error` (init-chown-data)

Acontece num redeploy de um Grafana que já tem dados na PVC: o container
`init-chown-data` roda como root mas sem a capability `CAP_DAC_OVERRIDE`
(só tem `CHOWN`), e falha ao tentar recursar em `pdf/`, `csv/`, `png/`
(que já existem com modo `700`, criados pelo próprio Grafana). Na
primeira subida (PVC vazia) esse container funciona normalmente; só
quebra depois. Como a dono já fica correta desde a primeira vez, esse
container é redundante - por isso `values.yaml` já sobe com
`initChownData.enabled: false`.

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
