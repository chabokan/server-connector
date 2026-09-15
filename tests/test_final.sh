#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

cat > "$TEST_DIR/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output_file=""
mode=json
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        --data-binary) mode=json; shift 2 ;;
        --data-urlencode) mode=query; shift 2 ;;
        -w) shift 2 ;;
        *) shift ;;
    esac
done
[[ -z "$output_file" ]] && exit 0  # readiness request
if [[ "$mode" == "json" ]]; then
    cat > "$MOCK_BODY_FILE"
    if [[ "$MOCK_API_MODE" == "new" ]]; then
        printf '{"success":true}\n' > "$output_file"
        printf '200'
    else
        printf '{"detail":[{"loc":["query","token"],"msg":"Field required"}]}\n' > "$output_file"
        printf '422'
    fi
else
    printf 'query\n' > "$MOCK_QUERY_FILE"
    printf '{"success":true}\n' > "$output_file"
    printf '200'
fi
EOF
chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/sleep"

for api_mode in new old; do
    rm -f "$TEST_DIR/body" "$TEST_DIR/query"
    PATH="$TEST_DIR/bin:$PATH" \
    TOKEN='test-token "quoted" & more' HUB_URL='https://hub.example.com/' COUNTRY=XX \
    INSTALL_LOG="$TEST_DIR/install.log" CONNECT_MAX_RETRIES=1 \
    MOCK_API_MODE="$api_mode" MOCK_BODY_FILE="$TEST_DIR/body" \
    MOCK_QUERY_FILE="$TEST_DIR/query" \
    bash "$REPO_DIR/utilities/final.sh" > "$TEST_DIR/output" 2>&1

    jq -e --arg token 'test-token "quoted" & more' \
        '.token == $token and .hub_url == "hub.example.com"' "$TEST_DIR/body" >/dev/null
    if [[ "$api_mode" == "old" ]]; then
        [[ -f "$TEST_DIR/query" ]]
    else
        [[ ! -f "$TEST_DIR/query" ]]
    fi
done
printf 'final.sh JSON and legacy query compatibility: ok\n'
