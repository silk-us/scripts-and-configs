#!/usr/bin/env bash
# FlexPrep-GCP.sh - collect project / quota / vpc / org-policy / iam info
# and dump it to a json file shaped like the aws/azure flexprep output.
# bash + gcloud + jq only, so it runs straight in cloud shell (no pwsh there).

set -uo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [-u SAS_URI] [-p PROJECT] [-n NETWORK] [-r REGION] [-g]
  -u, --uri      azure storage SAS uri to upload the json to (prompted if omitted)
  -p, --project  gcp project id (falls back to gcloud config, then a menu)
  -n, --network  only query this vpc network
  -r, --region   only query this region
  -g, --global   all regions (default is us-* only)
EOF
}

URI="" NETWORK="" PROJECT="" REGION="" GLOBAL=false
while [ $# -gt 0 ]; do
    case "$1" in
        -u|--uri)     URI="$2"; shift 2 ;;
        -p|--project) PROJECT="$2"; shift 2 ;;
        -n|--network) NETWORK="$2"; shift 2 ;;
        -r|--region)  REGION="$2"; shift 2 ;;
        -g|--global)  GLOBAL=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "unknown arg: $1"; usage; exit 1 ;;
    esac
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# little wrapper - run a gcloud cmd with --format=json and hand back parsed json.
# gcloud writes progress to stderr so we only care about stdout here.
# gcloud_json() {
#     local out
#     out=$(gcloud "$@" --format=json 2>/dev/null) || { echo "[]"; return; }
#     if [ -z "$out" ]; then echo "[]"; else echo "$out"; fi
# }
# ^ swallowed errors silently - empty sections in the json with zero clue why.
# now we keep stderr and warn so api-disabled / permission fails are visible.
gcloud_json() {
    local out
    if ! out=$(gcloud "$@" --format=json 2>"$tmpdir/gcloud_err"); then
        echo -e "${YELLOW}  warn: 'gcloud $*' failed: $(tail -n1 "$tmpdir/gcloud_err")${NC}" >&2
        echo "[]"
        return
    fi
    if [ -z "$out" ]; then echo "[]"; else echo "$out"; fi
}

# numbered menu over a list of values on stdin, picked value lands in MENU_PICK
menu_pick() {
    local message="$1"; shift
    local items=("$@")
    echo '------'
    local i
    for i in "${!items[@]}"; do
        echo "$((i+1)). ${items[$i]}"
    done
    echo '------'
    local sel
    read -r -p "$message: " sel
    MENU_PICK="${items[$((sel-1))]}"
    echo
}

# make sure gcloud and jq are actually here (they always are in cloud shell)
echo -e "${CYAN}Checking for gcloud CLI...${NC}"
if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "${RED}gcloud CLI not found. Run this from GCP Cloud Shell, or install the Google Cloud SDK.${NC}"
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}jq not found. Install jq (present by default in cloud shell).${NC}"
    exit 1
fi

# validate account / project context
echo -e "${CYAN}Validating GCP context...${NC}"

active_account=$(gcloud config get-value account 2>/dev/null)
if [ -z "$active_account" ]; then
    echo -e "${RED}No active gcloud account. Run 'gcloud auth login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}Active account: $active_account${NC}"

# project - param, else current config, else prompt from the list
if [ -z "$PROJECT" ]; then
    PROJECT=$(gcloud config get-value project 2>/dev/null)
fi
if [ -z "$PROJECT" ]; then
    mapfile -t proj_ids < <(gcloud_json projects list | jq -r '.[].projectId')
    if [ "${#proj_ids[@]}" -eq 0 ]; then
        echo -e "${RED}No projects available to this account.${NC}"
        exit 1
    fi
    menu_pick "Select Project" "${proj_ids[@]}"
    PROJECT="$MENU_PICK"
fi

# point gcloud at the chosen project for the rest of the run
gcloud config set project "$PROJECT" >/dev/null 2>&1

gcloud_json projects describe "$PROJECT" > "$tmpdir/project.json"
proj_name=$(jq -r 'if type=="object" then (.name // empty) else empty end' "$tmpdir/project.json")
proj_number=$(jq -r 'if type=="object" then (.projectNumber // empty) else empty end' "$tmpdir/project.json")
if [ -z "$proj_name" ]; then
    echo -e "${RED}Could not describe project '$PROJECT'. Check the id and your permissions.${NC}"
    exit 1
fi
echo -e "${GREEN}Using project: $proj_name ($PROJECT)${NC}"

# region quotas
echo -e "${CYAN}Retrieving compute regions and quotas...${NC}"

# which metrics we care about for a flex deploy - families come from gcp_skus.json
# (c4d/c3d standard+highmem cnodes, n2 highmem cnodes + n2 standard mnodes)
# quota_metrics='["CPUS","N2_CPUS","C2_CPUS","DISKS_TOTAL_GB","SSD_TOTAL_GB","LOCAL_SSD_TOTAL_GB","IN_USE_ADDRESSES","NETWORKS","SUBNETWORKS"]'   # c2 isnt a flex sku anymore, missing c3d/c4d
quota_metrics='["CPUS","N2_CPUS","C3D_CPUS","C4D_CPUS","DISKS_TOTAL_GB","SSD_TOTAL_GB","LOCAL_SSD_TOTAL_GB","IN_USE_ADDRESSES","NETWORKS","SUBNETWORKS"]'

gcloud_json compute regions list > "$tmpdir/regions.json"

# region filter: explicit region wins, else US only unless --global
jq --arg region "$REGION" --argjson global "$GLOBAL" \
    '[ .[]? | select(
        if $region != "" then .name == $region
        elif $global then true
        else (.name | startswith("us-")) end
    ) ]' "$tmpdir/regions.json" > "$tmpdir/regions_filtered.json"

region_count=$(jq 'length' "$tmpdir/regions_filtered.json")
echo -e "${CYAN}Processing $region_count region(s) for quota information...${NC}"

# zones come back as full self-links, trim to the short zone name
jq --argjson metrics "$quota_metrics" '[ .[] | {
    "Region": .name,
    "Availability Zones": ([ .zones[]? | split("/") | last ] | sort),
    "Quotas": [ .quotas[]? | select(.metric as $m | $metrics | index($m)) | {
        "Name": .metric,
        "Service": "compute",
        "Limit": .limit,
        "Current Usage": .usage
    } ]
} ]' "$tmpdir/regions_filtered.json" > "$tmpdir/region_quotas.json"

jq -r '.[].name' "$tmpdir/regions_filtered.json" | while read -r rn; do
    echo -e "${GRAY}  Checked quotas for region: $rn${NC}"
done

# vpc queries
# networks are global, subnets per-region - pull subnets+firewalls once, bucket by network
echo -e "${CYAN}Retrieving VPC network information...${NC}"

if [ -n "$NETWORK" ]; then
    gcloud_json compute networks list --filter="name=$NETWORK" > "$tmpdir/networks.json"
else
    gcloud_json compute networks list > "$tmpdir/networks.json"
fi

# grab all subnets + firewalls up front, filter in-memory per network
gcloud_json compute networks subnets list > "$tmpdir/subnets.json"
gcloud_json compute firewall-rules list > "$tmpdir/firewalls.json"

net_count=$(jq 'length' "$tmpdir/networks.json")
echo -e "${CYAN}Processing $net_count network(s)...${NC}"

jq -n --slurpfile nets "$tmpdir/networks.json" \
      --slurpfile subs "$tmpdir/subnets.json" \
      --slurpfile fws  "$tmpdir/firewalls.json" '
[ $nets[0][]? | . as $n | {
    "Name": .name,
    "Routing Mode": .routingConfig.routingMode,
    "Auto Create Subnets": .autoCreateSubnetworks,
    "MTU": .mtu,
    "Subnets": [ $subs[0][]? | select((.network | split("/") | last) == $n.name) |
        {
            "Name": .name,
            "Address Prefix": .ipCidrRange,
            "Region": (.region | split("/") | last),
            "Private Google Access": .privateIpGoogleAccess,
            "Gateway": .gatewayAddress
        }
        + (if .secondaryIpRanges then
            { "Secondary Ranges": [ .secondaryIpRanges[] | { "Range Name": .rangeName, "CIDR": .ipCidrRange } ] }
          else {} end)
    ],
    "Firewall Rules": [ $fws[0][]? | select((.network | split("/") | last) == $n.name) | {
        "Name": .name,
        "Direction": .direction,
        "Priority": .priority,
        "Action": (if .allowed then "ALLOW" elif .denied then "DENY" else "N/A" end),
        "Source Ranges": (.sourceRanges // []),
        "Destination Ranges": (.destinationRanges // []),
        "Rules": [ (.allowed // .denied // [])[] |
            "\(.IPProtocol):\(if .ports then (.ports | join(",")) else "all" end)" ]
    } ]
} ]' > "$tmpdir/vpc_networks.json"

jq -r '.[]?.name' "$tmpdir/networks.json" | while read -r nn; do
    echo -e "${GRAY}  Processed network: $nn${NC}"
done

# ancestors (folder/org) - iam grants and org policies usually live up the
# chain, not on the project itself. need these for the next two sections.
gcloud_json projects get-ancestors "$PROJECT" > "$tmpdir/ancestors.json"

# org policies (the gcp version of azure policy / aws SCPs)
# newer gcloud dropped 'resource-manager org-policies' for plain 'org-policies'
# with a different shape (name + spec.rules instead of constraint + listPolicy).
# try the new one first, fall back to legacy, normalize both to the same objects.
echo -e "${CYAN}Retrieving organization policies...${NC}"
gcloud_json org-policies list --project="$PROJECT" > "$tmpdir/op_project.json"
if [ "$(jq 'length' "$tmpdir/op_project.json")" -eq 0 ]; then
    gcloud_json resource-manager org-policies list --project="$PROJECT" > "$tmpdir/op_project.json"
fi

# policies set directly on a project are rare - orgs set them at folder/org
# level and they inherit down. walk the ancestry too. project stays first in
# the stream so it wins when the same constraint shows up twice.
cat "$tmpdir/op_project.json" > "$tmpdir/op_stream.json"
while IFS=$'\t' read -r atype aid; do
    case "$atype" in
        folder)       gcloud_json org-policies list --folder="$aid"       >> "$tmpdir/op_stream.json" ;;
        organization) gcloud_json org-policies list --organization="$aid" >> "$tmpdir/op_stream.json" ;;
    esac
done < <(jq -r '.[]? | select(.type != "project") | [.type, .id] | @tsv' "$tmpdir/ancestors.json")

jq -s 'map(if type == "array" then . else [] end) | add // []' "$tmpdir/op_stream.json" > "$tmpdir/org_policies_raw.json"

op_count=$(jq 'length' "$tmpdir/org_policies_raw.json")
echo -e "${CYAN}Processing $op_count org policy/policies (project + inherited)...${NC}"

# legacy: listPolicy vs booleanPolicy. new: spec.rules with enforce / values.
# unique_by keeps the first hit per constraint = the most specific level.
jq '[ .[]? |
    { "Constraint": (.constraint // (.name | split("/") | last)) }
    + (if .booleanPolicy then
        { "Type": "boolean", "Enforced": (.booleanPolicy.enforced // false) }
      elif .listPolicy then
        { "Type": "list",
          "Allowed Values": (.listPolicy.allowedValues // []),
          "Denied Values":  (.listPolicy.deniedValues // []) }
      elif .spec then
        (if ([ .spec.rules[]? | select(.enforce != null) ] | length) > 0 then
            { "Type": "boolean", "Enforced": ([ .spec.rules[]? | .enforce == true ] | any) }
        else
            { "Type": "list",
              "Allowed Values": ([ .spec.rules[]?.values.allowedValues // [] ] | add // []),
              "Denied Values":  ([ .spec.rules[]?.values.deniedValues  // [] ] | add // []) }
        end)
      else {} end)
] | unique_by(.Constraint)' "$tmpdir/org_policies_raw.json" > "$tmpdir/org_policies.json"

# operator iam roles + permissions
# pull the project iam policy, find the bindings the caller is in, describe each role for its perms
echo -e "${CYAN}Retrieving operator IAM roles and permissions...${NC}"

# first pass at this was a bash loop pulling fields out of each binding with
# jq -r and gluing the json back together from shell strings. worked but ugly.
# kept for reference:
#
# get_role_perms() {
#     local role="$1"
#     local cache_file="$tmpdir/role_$(echo "$role" | tr '/:.' '___').json"
#     if [ -f "$cache_file" ]; then cat "$cache_file"; return; fi
#     gcloud_json iam roles describe "$role" \
#         | jq -c 'if type=="object" then (.includedPermissions // []) else [] end' > "$cache_file"
#     cat "$cache_file"
# }
# while IFS= read -r binding; do
#     role=$(jq -r '.role' <<<"$binding")
#     direct=$(jq --arg u "$user_member" '[ .members[]? == $u ] | any' <<<"$binding")
#     groups=$(jq -c '[ .members[]? | select(startswith("group:") or startswith("domain:")) ]' <<<"$binding")
#     if [ "$direct" != "true" ] && [ "$(jq 'length' <<<"$groups")" -eq 0 ]; then continue; fi
#     if [ "$direct" = "true" ]; then assignment_type="User (Direct)"
#     else assignment_type="Group/Domain ($(jq -r 'join(", ")' <<<"$groups"))"; fi
#     perms=$(get_role_perms "$role")
#     is_custom=false
#     case "$role" in projects/*|organizations/*) is_custom=true ;; esac
#     jq -n --arg role "$role" ... >> "$tmpdir/iam_roles.jsonl"
# done < <(jq -c '.bindings[]?' "$tmpdir/iam_policy.json")

gcloud_json projects get-iam-policy "$PROJECT" > "$tmpdir/iam_policy.json"

# member strings we count as "the operator": the user themselves, plus any
# group/domain binding (cant cheaply expand group membership from gcloud, so
# we surface group bindings and note them).
user_member="user:$active_account"

# v1 kept only bindings the operator appeared in:
# jq --arg u "$user_member" '[ .bindings[]?
#     | select(
#         ((.members // []) | index($u))
#         or ([ .members[]? | select(startswith("group:") or startswith("domain:")) ] | length > 0)
#     ) ]' "$tmpdir/iam_policy.json" > "$tmpdir/op_bindings.json"
# ^ came back empty on org-managed projects - the humans are granted at the
# folder/org level and the project policy is all service accounts. so now:
# keep EVERY project binding (labeled), and chase the operator up the ancestry.

jq --arg s "projects/$PROJECT" \
    '[ (if type == "object" then (.bindings // []) else [] end)[] | . + { "scope": $s } ]' \
    "$tmpdir/iam_policy.json" > "$tmpdir/bindings_stream.json"

# folder/org bindings - just the ones that mention the operator. these 403
# for plenty of users, thats fine, gcloud_json warns and moves on.
while IFS=$'\t' read -r atype aid; do
    case "$atype" in
        folder)       gcloud_json resource-manager folders get-iam-policy "$aid" > "$tmpdir/anc_policy.json"; ascope="folders/$aid" ;;
        organization) gcloud_json organizations get-iam-policy "$aid" > "$tmpdir/anc_policy.json"; ascope="organizations/$aid" ;;
        *) continue ;;
    esac
    jq --arg s "$ascope" --arg u "$user_member" \
        '[ (if type == "object" then (.bindings // []) else [] end)[]
            | select(
                ((.members // []) | index($u))
                or ([ .members[]? | select(startswith("group:") or startswith("domain:")) ] | length > 0)
            )
            | . + { "scope": $s } ]' "$tmpdir/anc_policy.json" >> "$tmpdir/bindings_stream.json"
done < <(jq -r '.[]? | select(.type != "project") | [.type, .id] | @tsv' "$tmpdir/ancestors.json")

jq -s 'map(if type == "array" then . else [] end) | add // []' "$tmpdir/bindings_stream.json" > "$tmpdir/all_bindings.json"

binding_count=$(jq 'length' "$tmpdir/all_bindings.json")
echo -e "${CYAN}Processing $binding_count IAM binding(s) across project + ancestors...${NC}"

# describe each unique role once, collect into a role -> permissions map
echo '{}' > "$tmpdir/role_perms.json"
while IFS= read -r role; do
    echo -e "${GRAY}  Describing role: $role${NC}"
    gcloud_json iam roles describe "$role" \
        | jq -c 'if type=="object" then (.includedPermissions // []) else [] end' > "$tmpdir/perms_one.json"
    jq --arg r "$role" --slurpfile p "$tmpdir/perms_one.json" '. + { ($r): $p[0] }' \
        "$tmpdir/role_perms.json" > "$tmpdir/role_perms.tmp" && mv "$tmpdir/role_perms.tmp" "$tmpdir/role_perms.json"
done < <(jq -r '.[].role' "$tmpdir/all_bindings.json" | sort -u)

# all the shaping lives in jq now - match the standardized role object shape
# (Role Name / Scope / Actions), same as the azure/aws scripts emit.
jq --arg u "$user_member" --slurpfile perms "$tmpdir/role_perms.json" '
[ .[] | {
    "Role Name": .role,
    "Scope": .scope,
    "Assignment Type": (
        if ((.members // []) | index($u)) then "User (Direct)"
        elif ([ .members[]? | select(startswith("group:") or startswith("domain:")) ] | length) > 0 then
            "Group/Domain (\([ .members[]? | select(startswith("group:") or startswith("domain:")) ] | join(", ")))"
        else "Other Principals" end),
    "Is Custom": (.role | (startswith("projects/") or startswith("organizations/"))),
    "Actions": ($perms[0][.role] // []),
    "Members": (.members // [])
} ]' "$tmpdir/all_bindings.json" > "$tmpdir/iam_roles.json"

echo -e "${CYAN}Processed $(jq 'length' "$tmpdir/iam_roles.json") role binding(s).${NC}"

# write the json out
# gcp has no PIM so that array stays empty, keeps the schema parallel with azure.
echo -e "${CYAN}Generating JSON output file...${NC}"
filedate=$(date +%Y%m%d-%H%M%S)
output_file="$PROJECT-$filedate.json"

jq -n --arg pname "$proj_name" --arg pid "$PROJECT" --arg pnum "$proj_number" \
      --slurpfile rq  "$tmpdir/region_quotas.json" \
      --slurpfile vpc "$tmpdir/vpc_networks.json" \
      --slurpfile op  "$tmpdir/org_policies.json" \
      --slurpfile ir  "$tmpdir/iam_roles.json" \
    '{
        "Project": $pname,
        "Project ID": $pid,
        "Project Number": $pnum,
        "Region Quotas": $rq[0],
        "VPC Networks": $vpc[0],
        "Org Policies": $op[0],
        "IAM": { "IAMRoles": $ir[0], "PIMRoles": [] }
    }' > "$output_file"

if [ ! -s "$output_file" ]; then
    echo -e "${RED}Error creating JSON file.${NC}"
    exit 1
fi
echo -e "${GREEN}JSON file created: $output_file${NC}"

# upload to azure storage via the SAS uri (same target the other flexprep scripts use)
if [ -z "$URI" ]; then
    read -r -p "Azure Storage SAS URI for upload (blank to skip): " URI
fi

if [ -n "$URI" ]; then
    echo -e "${CYAN}Uploading file to Azure Storage...${NC}"
    base="${URI%%\?*}"
    query="${URI#*\?}"
    if [ "$query" = "$URI" ]; then query=""; else query="?$query"; fi
    blob_url="$base/$output_file$query"

    if curl -fsS -X PUT \
        -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Type: application/json" \
        --data-binary "@$output_file" \
        "$blob_url" >/dev/null; then
        echo -e "${GREEN}File uploaded successfully: $base/$output_file${NC}"
    else
        echo -e "${RED}Error uploading file to Azure Storage.${NC}"
        echo -e "${YELLOW}Local file available at: $output_file${NC}"
    fi
fi
