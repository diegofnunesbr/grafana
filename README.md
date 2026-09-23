# grafana

Instalação do **Grafana** via chart oficial (`grafana/grafana`), usando uma
Application multi-source do Argo CD: o chart vem direto do repositório
Helm da Grafana, e os `values.yaml` (datasource do Mimir, dashboards,
persistência, etc.) vêm deste repositório.

## Pré-requisitos

- `Kubernetes` instalado
- `kubectl` e `kubeseal` instalados
- ArgoCD instalado (ver repositório `argocd`)
- `Sealed Secrets` e `cert-manager` instalados (via `core-config` do
  repositório `argocd` e repositório `cert-manager`)
- `ingress-nginx` instalado (repositório `ingress-nginx`)
- DNS `grafana.diegofnunesbr.com` apontando pro node (ver repositório `dns`)
- Repositório `mimir` já instalado (o datasource padrão aponta pra ele)
- Contexto `k0s` no seu kubeconfig (ver README do repositório `argocd`,
  seção "Acessar o cluster de fora da VM"), usado pelo `change-admin-password.sh`

## Estrutura do repositório

```text
grafana/
├── applications/
│   └── argocd.grafana.yaml     # Application multi-source do Argo CD
├── secrets/
│   └── grafana-admin-secret.sealed.yaml  # senha do admin (selada, aplicada pelo Argo CD)
├── change-admin-password.sh    # troca a senha do admin
├── values.yaml                 # values do chart oficial grafana/grafana
└── README.md
```

## Senha do admin

A senha fica selada em `secrets/grafana-admin-secret.sealed.yaml`, que a
própria Application aplica (terceira source). Pra trocar (ou num cluster
novo, com outra chave do Sealed Secrets), rode daqui do seu clone:

```bash
./change-admin-password.sh
```

Ele pede a senha sem ecoar, sela, faz commit + push e aplica a senha no
Grafana rodando (`grafana cli admin reset-admin-password` dentro do pod).
Esse último passo é necessário porque o Grafana só lê a senha do secret na
**primeira** subida (quando cria o banco); depois disso ela vive no banco
dele, e mudar só o secret não muda o login.

## Instalar o Grafana

```bash
git clone https://github.com/diegofnunesbr/grafana.git
cd grafana
kubectl apply -f applications/argocd.grafana.yaml
```

**Lembrete:** a Application aponta pro GitHub (`repoURL`), não pro seu
clone local - qualquer mudança em `values.yaml` só tem efeito depois de
`git push` (e um sync, automático ou forçado via
`kubectl -n argocd patch application grafana --type merge -p '{"operation":{"sync":{}}}'`).

## Acessar

```text
https://grafana.diegofnunesbr.com
```

Login `admin` + senha da seção "Senha do admin". Certificado real
(Let's Encrypt, renovado automaticamente pelo cert-manager) - sem porta
na URL. Se precisar de acesso direto sem depender do Ingress/DNS (debug):

```bash
kubectl -n grafana port-forward svc/grafana 3000:80
```

## Dashboards

Nenhum dashboard vem pronto: você cria (ou importa) pela própria interface.
Só o datasource `Mimir` é provisionado pelo `values.yaml`.

Pra importar um dashboard da comunidade, como o Node Exporter Full:
`Dashboards → New → Import`, digite o ID (`1860` pro Node Exporter Full),
clique em `Load`, escolha o datasource `Mimir` e `Import`.

Os dashboards ficam no banco do Grafana, dentro da PVC (`persistence`),
então sobrevivem a restart, redeploy e atualização do chart. **Eles não
ficam no git**: numa reinstalação do cluster do zero (ou se a PVC for
apagada), somem. Pra guardar um, exporte o JSON (`Export → Export as
JSON`) e salve em algum lugar; pra restaurar, `Dashboards → New →
Import` e cole o JSON.

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
kubectl -n grafana port-forward svc/grafana 13000:80 &
curl -s -u admin http://localhost:13000/api/health
curl -s -u admin http://localhost:13000/api/datasources
```

Com `-u admin` (sem `:senha`) o `curl` pede a senha interativamente, então
ela não fica no histórico do shell.

O `/api/health` deve responder `"database":"ok"`, e `/api/datasources`
deve listar o datasource `Mimir` com `"isDefault":true`.

## Remover o Grafana

```bash
cd grafana
kubectl delete -f applications/argocd.grafana.yaml
```
