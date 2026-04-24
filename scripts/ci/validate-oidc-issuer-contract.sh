#!/usr/bin/env bash
# @file        scripts/ci/validate-oidc-issuer-contract.sh
# @module      ci/security
# @description Validate the OIDC issuer/auth contract across issuer, proxy, and env templates
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_FILE="${1:-$ROOT_DIR/artifacts/security/oidc-issuer-contract-report.json}"

FILES=(
  "$ROOT_DIR/config/iam/k8s-oidc.env.template"
  "$ROOT_DIR/config/iam/k8s-oidc-issuer.yaml"
  "$ROOT_DIR/config/iam/k8s-oidc-issuer-production.yaml"
  "$ROOT_DIR/config/caddy/oidc-issuer-routing.caddyfile"
  "$ROOT_DIR/config/iam/oidc-proxy.caddyfile"
)

require_command "python3" "python3 is required"
for file in "${FILES[@]}"; do
  require_file "$file"
done

mkdir -p "$(dirname "$REPORT_FILE")"

python3 - "$REPORT_FILE" "${FILES[@]}" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

report_path = sys.argv[1]
file_paths = [Path(p) for p in sys.argv[2:]]
contents = {path.name: path.read_text(encoding='utf-8') for path in file_paths}

errors = []
warnings = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def warn(condition: bool, message: str) -> None:
    if not condition:
        warnings.append(message)

env_template = contents['k8s-oidc.env.template']
issuer_yaml = contents['k8s-oidc-issuer.yaml']
issuer_prod = contents['k8s-oidc-issuer-production.yaml']
caddy_routing = contents['oidc-issuer-routing.caddyfile']
caddy_proxy = contents['oidc-proxy.caddyfile']

def has(text: str, needle: str) -> bool:
    return needle in text

def regex(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.MULTILINE) is not None

# env template checks
require(has(env_template, 'K8S_OIDC_ISSUER="https://oidc.prod.internal"'), 'env template must pin the on-prem issuer')
require(has(env_template, 'K8S_OIDC_DISCOVERY_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/openid-configuration"'), 'env template must derive discovery endpoint from issuer')
require(has(env_template, 'K8S_OIDC_JWKS_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/jwks.json"'), 'env template must derive JWKS endpoint from issuer')
for key in (
    'KUBE_SA_CODE_SERVER_ROLE="workload/viewer"',
    'KUBE_SA_BACKSTAGE_ROLE="workload/operator"',
    'KUBE_SA_APPSMITH_ROLE="workload/operator"',
    'KUBE_SA_OLLAMA_ROLE="workload/viewer"',
    'KUBE_SA_PROMETHEUS_ROLE="workload/viewer"',
    'KUBE_SA_LOKI_ROLE="workload/viewer"',
):
    require(has(env_template, key), f'env template missing role mapping: {key}')

# issuer YAML checks
require(has(issuer_yaml, 'kind: ConfigMap'), 'issuer yaml must define a ConfigMap')
require(has(issuer_yaml, 'issuer: "https://oidc.kushnir.cloud:8080"'), 'issuer yaml must pin the external issuer URL')
require(has(issuer_yaml, 'client_id: "code-server-services"'), 'issuer yaml must define the service client id')
require(has(issuer_yaml, 'audiences: "code-server,prometheus,loki,grafana,redis,postgresql"'), 'issuer yaml must define the audience set')
require(has(issuer_yaml, 'resourceNames: ["default-token"]'), 'issuer yaml must restrict token secret access')
require(has(issuer_yaml, 'automountServiceAccountToken: true'), 'issuer yaml must enable service account token mounting for issuer bootstrap')
require(has(issuer_yaml, 'kind: ServiceAccount'), 'issuer yaml must define a service account for issuer access')
require(has(issuer_yaml, 'kind: Role'), 'issuer yaml must define a namespaced role')
require(has(issuer_yaml, 'kind: RoleBinding'), 'issuer yaml must define a namespaced role binding')
require(has(issuer_yaml, 'kind: ClusterRole'), 'issuer yaml must define a cluster role')
require(has(issuer_yaml, 'kind: ClusterRoleBinding'), 'issuer yaml must define a cluster role binding')
require(has(issuer_yaml, 'resourceNames: ["default-token"]'), 'issuer yaml must keep token secret access scoped to the default token')

# production issuer checks
require(has(issuer_prod, 'namespace: oidc-issuer'), 'production issuer yaml must use the oidc-issuer namespace')
require(has(issuer_prod, 'issuer: https://oidc.kushnir.cloud'), 'production issuer yaml must pin the public issuer URL')
require(has(issuer_prod, 'redirectURIs:'), 'production issuer yaml must define static client redirect URIs')
require(has(issuer_prod, 'https://ide.kushnir.cloud/callback'), 'production issuer yaml must include the IDE redirect URI')
require(has(issuer_prod, 'https://grafana.kushnir.cloud/login/generic_oauth'), 'production issuer yaml must include the Grafana redirect URI')
require(has(issuer_prod, 'secret: code-server-secret-do-not-use-in-prod'), 'production issuer yaml must flag placeholder client secret material')
require(has(issuer_prod, 'secretName: oidc-signing-key'), 'production issuer yaml must reference the signing secret')
require(has(issuer_prod, 'replicas: 3'), 'production issuer yaml must default to three replicas')
require(has(issuer_prod, 'image: dexidp/dex:v2.35.3'), 'production issuer yaml must pin the Dex image')
require(has(issuer_prod, 'secretName: oidc-signing-key'), 'production issuer yaml must reference the signing secret')
require(has(issuer_prod, 'ClusterIP'), 'production issuer yaml must expose the issuer internally only')
require(has(issuer_prod, 'maxUnavailable: 0'), 'production issuer yaml must avoid availability loss during rollout')
require(has(issuer_prod, 'maxSurge: 1'), 'production issuer yaml must keep rolling updates conservative')
require(has(issuer_prod, 'defaultMode: 0400'), 'production issuer yaml must lock the signing key secret permissions')

# caddy routing checks
require(has(caddy_routing, 'oidc.{$APEX_DOMAIN}'), 'OIDC routing caddyfile must bind the oidc subdomain')
require(has(caddy_routing, 'reverse_proxy http://oidc-issuer.oidc-issuer.svc.cluster.local:8888'), 'OIDC routing must reverse proxy to the issuer service')
require(has(caddy_routing, 'handle /.well-known/openid-configuration'), 'OIDC routing must expose discovery')
require(has(caddy_routing, 'handle /.well-known/jwks.json'), 'OIDC routing must expose JWKS')

# proxy caddyfile checks
require(has(caddy_proxy, 'oidc.{$APEX_DOMAIN}'), 'OIDC proxy caddyfile must bind the oidc subdomain')
require(has(caddy_proxy, 'replace_uri /openid/$1'), 'OIDC proxy caddyfile must rewrite /oidc paths to openid paths')
require(has(caddy_proxy, 'route /.well-known/openid-configuration'), 'OIDC proxy caddyfile must serve discovery')
require(has(caddy_proxy, 'route /.well-known/openid-configuration/jwks'), 'OIDC proxy caddyfile must serve JWKS')
require(has(caddy_proxy, 'header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"'), 'OIDC proxy caddyfile must enforce HSTS')

warn(has(issuer_prod, 'mockCallback'), 'production issuer yaml still includes a mock connector; confirm it is dev-only before rollout')

summary = {
    'file_count': len(file_paths),
    'error_count': len(errors),
    'warning_count': len(warnings),
    'validated_contracts': [
        'k8s-oidc.env.template',
        'k8s-oidc-issuer.yaml',
        'k8s-oidc-issuer-production.yaml',
        'oidc-issuer-routing.caddyfile',
        'oidc-proxy.caddyfile',
    ],
}

report = {
    'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'summary': summary,
    'errors': errors,
    'warnings': warnings,
}

Path(report_path).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

print(f'OIDC issuer contract report: {report_path}')
print(f'Errors: {len(errors)}')
print(f'Warnings: {len(warnings)}')

if errors:
    sys.exit(1)
PY

log_info "OIDC issuer contract validated"
log_info "Report written: $REPORT_FILE"