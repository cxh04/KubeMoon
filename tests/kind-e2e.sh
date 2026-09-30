#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
cluster="kubemoon-e2e-${GITHUB_RUN_ID:-local}"
if kind get clusters | grep -Fxq "$cluster"; then
  echo "Refusing to reuse existing kind cluster: $cluster" >&2
  exit 1
fi

created=0
cleanup() {
  result=$?
  if (( created )); then
    if (( result != 0 )); then
      k -n kubemoon-system logs deploy/kubemoon-configmirror --all-containers --tail=200 || true
      k -n kubemoon-system describe pods || true
      k get configmirrors -A -o yaml || true
    fi
    kind delete cluster --name "$cluster"
  fi
  exit "$result"
}
trap cleanup EXIT

k() { kubectl --context "kind-$cluster" "$@"; }
eventually() {
  for _ in $(seq 1 120); do
    if "$@"; then return 0; fi
    sleep 1
  done
  echo "Timed out waiting for: $*" >&2
  return 1
}
has_data() {
  local namespace=$1 expected=$2 value
  value=$(k -n "$namespace" get configmap settings -o jsonpath='{.data.key}' 2>/dev/null) || return 1
  [[ "$value" == "$expected" ]]
}
missing_target() {
  ! k -n "$1" get configmap settings >/dev/null 2>&1
}
mirror_gone() {
  ! k -n ops get configmirror mirror >/dev/null 2>&1
}
status_ready() {
  local hash targets
  hash=$(k -n ops get configmirror mirror -o jsonpath='{.status.contentHash}' 2>/dev/null) || return 1
  targets=$(k -n ops get configmirror mirror -o jsonpath='{.status.syncedTargets[*]}' 2>/dev/null) || return 1
  [[ ${#hash} -eq 64 && "$targets" == "west east" ]]
}

moon build cmd/configmirror --target native --release
test -x _build/native/release/build/cmd/configmirror/configmirror.exe
docker build -f deploy/Dockerfile -t kubemoon-configmirror:e2e \
  _build/native/release/build/cmd/configmirror
kind create cluster --name "$cluster" --wait 120s
created=1
kind load docker-image kubemoon-configmirror:e2e --name "$cluster"

k apply -f deploy/configmirror-crd.yaml
k wait --for=condition=Established crd/configmirrors.kubemoon.cxh04.github.io --timeout=120s
k apply -f deploy/configmirror-controller.yaml
k -n kubemoon-system rollout status deploy/kubemoon-configmirror --timeout=120s
for namespace in source west east ops; do k create namespace "$namespace"; done
k -n source create configmap settings --from-literal=key=initial
k apply -f - <<'YAML'
apiVersion: kubemoon.cxh04.github.io/v1alpha1
kind: ConfigMirror
metadata:
  name: mirror
  namespace: ops
spec:
  source:
    namespace: source
    name: settings
  targets: [west, east]
YAML

eventually has_data west initial
eventually has_data east initial
eventually status_ready

k -n source create configmap settings --from-literal=key=updated \
  --dry-run=client -o yaml | k apply -f -
eventually has_data west updated
eventually has_data east updated

k -n west delete configmap settings
eventually has_data west updated

k -n kubemoon-system rollout restart deploy/kubemoon-configmirror
k -n kubemoon-system rollout status deploy/kubemoon-configmirror --timeout=120s
k -n source create configmap settings --from-literal=key=after-restart \
  --dry-run=client -o yaml | k apply -f -
eventually has_data west after-restart
eventually has_data east after-restart

k -n ops delete configmirror mirror --wait=false
eventually mirror_gone
eventually missing_target west
eventually missing_target east
echo "ConfigMirror kind lifecycle passed"
