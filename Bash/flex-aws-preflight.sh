#!/bin/bash
# Flex-on-AWS preflight — run on the Flex VM (SSM session / SSH).
# Read-only. Checks every external dependency Flex needs, classifies
# each failure as ROUTING (timeout) vs POLICY (AccessDenied) vs OK.
# Requires: aws CLI (present on Flex VMs), curl. ~30 seconds.

set -u
VERBOSE=0
case "${1:-}" in -v|--verbose) VERBOSE=1;; esac
vecho() { [ "$VERBOSE" = 1 ] && echo "  [v] $*"; return 0; }
vout()  { [ "$VERBOSE" = 1 ] && [ -n "${1:-}" ] && sed 's/^/  [v] /' <<<"$1"; return 0; }
PASS=(); FAIL=(); WARN=()
ok()   { echo "  [OK]   $1"; PASS+=("$1"); }
bad()  { echo "  [FAIL] $1"; FAIL+=("$1"); }
warn() { echo "  [WARN] $1"; WARN+=("$1"); }

# --- region + identity from instance metadata (IMDSv2) ---
TOK=$(curl -s -m 3 -X PUT http://169.254.169.254/latest/api/token \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
REGION=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $TOK" \
      http://169.254.169.254/latest/meta-data/placement/region)
ACCOUNT_HINT=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $TOK" \
      http://169.254.169.254/latest/dynamic/instance-identity/document \
      | grep -oP '(?<="accountId" : ")[^"]*')
echo "Region: ${REGION:-UNKNOWN} | Account: ${ACCOUNT_HINT:-UNKNOWN}"
echo

# --- 1. DNS path + raw TCP connect (localizes failures; see matrix) ---
echo "=== DNS paths + TCP connect ==="
echo "  How to read failures (DNS class + TCP connect + API check below):"
echo "    public            + CONNECT-FAIL                  => no egress route (TGW/NAT/firewall)"
echo "    PRIVATE(endpoint) + CONNECT-FAIL                  => route/SG to the endpoint ENI (hub-VPC plumbing)"
echo "    PRIVATE(endpoint) + connect-OK + POLICY-DENIED    => VPC endpoint policy (or SCP/RCP)"
echo "    connect-OK        + API check OK                  => healthy"
echo
for h in sts.$REGION.amazonaws.com ec2.$REGION.amazonaws.com \
         servicequotas.$REGION.amazonaws.com s3.$REGION.amazonaws.com \
         api.ecr.$REGION.amazonaws.com hub.clarity.silk.us; do
  ip=$(getent hosts "$h" | awk '{print $1}' | head -1)
  case "$ip" in
    10.*|100.6[4-9].*|100.[7-9]*|100.1[0-2]*|172.1[6-9].*|172.2*|172.3[01].*|192.168.*)
        cls="PRIVATE(endpoint)";;
    "") cls="NO-DNS";;
    *)  cls="public";;
  esac
  if [ -n "$ip" ]; then
    if curl -s -o /dev/null --connect-timeout 5 "https://$h/" 2>/dev/null; then
      conn="connect-OK"
    else conn="CONNECT-FAIL"; fi
  else conn="—"; fi
  printf "  %-45s %-16s %-18s %s\n" "$h" "${ip:-—}" "$cls" "$conn"
done
echo

# --- 2. STS: identity (endpoint-policy trap detector) ---
echo "=== STS GetCallerIdentity ==="
vecho "cmd: aws sts get-caller-identity --region $REGION"
out=$(timeout 12 aws sts get-caller-identity --region "$REGION" 2>&1)
vout "$out"
if   grep -q '"Arn"' <<<"$out"; then ok "STS: $(grep -oP '(?<="Arn": ")[^"]*' <<<"$out")"
elif grep -qi 'AccessDenied' <<<"$out"; then bad "STS POLICY-DENIED (endpoint policy/SCP/RCP): $(head -c 200 <<<"$out")"
else bad "STS unreachable/timeout (ROUTING): $(head -c 150 <<<"$out")"; fi
echo

# --- 3. EC2 ---
echo "=== EC2 DescribeVpcs ==="
vecho "cmd: aws ec2 describe-vpcs --region $REGION"
out=$(timeout 12 aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[].VpcId' --output text 2>&1)
vout "$out"
if   grep -q '^vpc-' <<<"$out"; then ok "EC2: sees VPC(s): $out"
elif grep -qi 'UnauthorizedOperation\|AccessDenied' <<<"$out"; then bad "EC2 POLICY-DENIED: $(head -c 200 <<<"$out")"
else bad "EC2 unreachable/timeout (ROUTING): $(head -c 150 <<<"$out")"; fi
echo

# --- 4. Service Quotas (used by SDP validate_create; NOT in the endpoint deck!) ---
echo "=== Service Quotas ==="
vecho "cmd: aws service-quotas list-service-quotas --service-code ec2 --max-items 1 --region $REGION"
out=$(timeout 12 aws service-quotas list-service-quotas --service-code ec2 \
      --max-items 1 --region "$REGION" 2>&1)
[ "$VERBOSE" = 1 ] && vout "$(head -c 500 <<<"$out")"
if   grep -q 'QuotaCode\|Quotas' <<<"$out"; then ok "Service Quotas reachable"
elif grep -qi 'AccessDenied' <<<"$out"; then bad "ServiceQuotas POLICY-DENIED: $(head -c 200 <<<"$out")"
else bad "ServiceQuotas unreachable/timeout (ROUTING) => SDP validate_create will 504. Fix: com.amazonaws.$REGION.servicequotas endpoint (Principal:\"*\" + aws:PrincipalAccount) or skip_quotas_validation"; fi
echo

# --- 5. S3 (callhome upload target) ---
echo "=== S3 reachability ==="
code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "https://s3.$REGION.amazonaws.com")
case "$code" in
  307|405|403|200) ok "S3 reachable (HTTP $code)";;
  000) bad "S3 unreachable (ROUTING) — callhome uploads impossible";;
  *)   warn "S3 answered HTTP $code — verify";;
esac
echo

# --- 6. Clarity hub (callhome control plane) ---
echo "=== Clarity Hub (hub.clarity.silk.us:443) ==="
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 https://hub.clarity.silk.us)
if [ "$code" = "000" ]; then
  [ "$VERBOSE" = 1 ] && vout "$(curl -sv -o /dev/null -m 10 https://hub.clarity.silk.us 2>&1 | grep -E '^\*' | head -8)"
  bad "hub.clarity.silk.us unreachable (ROUTING/firewall) — callhome blocked"
else ok "hub.clarity.silk.us reachable (HTTP $code)"; fi
echo

# --- 7. ECR api (image pulls) ---
echo "=== ECR API reachability ==="
code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "https://api.ecr.$REGION.amazonaws.com")
if [ "$code" = "000" ]; then bad "ECR API unreachable (ROUTING)"; else ok "ECR API reachable (HTTP $code)"; fi
echo

# --- 8. Silk AMIs visibility (manual-share flow on 9.5.20) ---
echo "=== Silk AMIs visible in this account/region ==="
out=$(timeout 15 aws ec2 describe-images --region "$REGION" \
      --filters "Name=name,Values=k2c-cnode-*,aws-dnode-*" \
      --query 'Images[].[Name,ImageId,OwnerId]' --output text 2>&1)
if grep -qi 'UnauthorizedOperation\|AccessDenied' <<<"$out"; then
  bad "DescribeImages POLICY-DENIED: $(head -c 150 <<<"$out")"
elif [ -z "$out" ]; then
  warn "No Silk c/d-node AMIs visible. Either not shared yet, or the account's 'Allowed AMIs' allow-list blocks 3rd-party shares (check: aws ec2 get-allowed-images-settings --region $REGION)"
else
  echo "$out" | sed 's/^/  /'
  ok "Silk AMIs visible (OwnerId = Silk account => shares work; OwnerId = this account => locally copied)"
  grep -q 'aws-dnode' <<<"$out" || warn "No dnode AMI visible — SDP validate will report missing_artifacts"
  grep -q 'k2c-cnode' <<<"$out" || warn "No cnode AMI visible"
fi
echo

# --- verbose only: VPC endpoint inventory (what private doors exist + custom policies) ---
if [ "$VERBOSE" = 1 ]; then
  echo "=== [v] VPC endpoints in $REGION ==="
  timeout 15 aws ec2 describe-vpc-endpoints --region "$REGION" \
    --query 'VpcEndpoints[].[VpcEndpointId,ServiceName,State,VpcId]' --output text 2>&1 \
    | sed 's/^/  /' || echo "  (could not list — needs ec2:DescribeVpcEndpoints)"
  echo
fi

# --- summary ---
echo "==================== SUMMARY ===================="
for p in "${PASS[@]:-}"; do [ -n "$p" ] && echo "  PASS: $p"; done
for w in "${WARN[@]:-}"; do [ -n "$w" ] && echo "  WARN: $w"; done
for f in "${FAIL[@]:-}"; do [ -n "$f" ] && echo "  FAIL: $f"; done
[ ${#FAIL[@]} -eq 0 ] && echo "  All critical checks passed." || echo "  ${#FAIL[@]} failing — see classifications above (timeout=ROUTING, AccessDenied=POLICY)."
