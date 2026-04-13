
#!/bin/bash
# Priority-Based Issue Management CLI
# Usage: ./priority-issue-cli.sh <action> [options]

set -euo pipefail

# Configuration
REPO="${GITHUB_REPO:-kushin77/code-server}"
TOKEN="${GITHUB_TOKEN:-}"
API_BASE="https://api.github.com"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Functions
check_token() {
    if [[ -z "$TOKEN" ]]; then
        echo "❌ GITHUB_TOKEN environment variable not set"
        exit 1
    fi
}

print_usage() {
    cat << EOF
Priority Issue Management CLI
=============================

Usage: $0 <action> [options]

ACTIONS:

  create [options]
    Create a new prioritized issue
    Options:
      --title <text>        Issue title (REQUIRED)
      --body <text>         Issue body/description
      --priority <P0|P1|P2|P3>  Priority level (default: P1)
      --labels <l1,l2,...>  Additional labels (comma-separated)
      --assignee <user>     Assign to user
      --milestone <text>    Add to milestone

  list [options]
    List issues by priority
    Options:
      --priority <P0|P1|P2|P3|all>  Filter by priority (default: all)
      --state <open|closed|all>     Filter by state (default: open)
      --count <n>           Number of issues to show (default: 10)

  next
    Get the highest priority open issue

  assign <issue-number> <username>
    Assign issue to user and set appropriate priority

  set-priority <issue-number> <P0|P1|P2|P3>
    Update issue priority

  priority-stats
    Show priority distribution statistics

EXAMPLES:

  # Create a critical issue
  $0 create --title "Production outage" --priority P0 --body "System is down"

  # List all P0 issues
  $0 list --priority P0 --count 20

  # Get next highest priority issue to work on
  $0 next

  # Set an existing issue to high priority
  $0 set-priority 123 P1

EOF
}

api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local args=(
        -s
        -X "$method"
        -H "Authorization: Bearer $TOKEN"
        -H "Accept: application/vnd.github.v3+json"
        -H "Content-Type: application/json"
    )
    
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi
    
    curl "${args[@]}" "$API_BASE$endpoint"
}

create_issue() {
    local title="$1"
    local body="${2:-}"
    local priority="${3:-P1}"
    local labels="${4:-}"
    local assignee="${5:-}"
    
    # Validate priority
    if ! [[ "$priority" =~ ^P[0-3]$ ]]; then
        echo "❌ Invalid priority: $priority"
        echo "   Use: P0, P1, P2, or P3"
        exit 1
    fi
    
    # Build labels array
    local all_labels=("$priority" "prioritized")
    if [[ -n "$labels" ]]; then
        IFS=',' read -ra custom_labels <<< "$labels"
        all_labels+=("${custom_labels[@]}")
    fi
    
    # Build JSON payload
    local json_labels=$(printf '%s\n' "${all_labels[@]}" | jq -R -s -c 'split("\n")[:-1]')
    
    local payload="{
        \"title\": $(echo "$title" | jq -R .),
        \"body\": $(echo "$body" | jq -R .),
        \"labels\": $json_labels"
    
    if [[ -n "$assignee" ]]; then
        payload+=",\"assignee\": $(echo "$assignee" | jq -R .)"
    fi
    
    payload+="}"
    
    echo "Creating issue with priority $priority..."
    
    local response=$(api_call POST "/repos/$REPO/issues" "$payload")
    local issue_number=$(echo "$response" | jq -r '.number // empty')
    
    if [[ -n "$issue_number" ]]; then
        local url=$(echo "$response" | jq -r '.html_url')
        echo -e "${GREEN}✅ Issue #$issue_number created${NC}"
        echo "   Priority: $priority"
        echo "   Title: $title"
        echo "   URL: $url"
    else
        echo -e "${RED}❌ Failed to create issue${NC}"
        echo "$response" | jq '.'
        exit 1
    fi
}

list_issues() {
    local priority="${1:-all}"
    local state="${2:-open}"
    local count="${3:-10}"
    
    # Build query
    local query="repo:$REPO is:issue is:$state"
    if [[ "$priority" != "all" ]]; then
        query+=" label:$priority"
    fi
    
    echo -e "${CYAN}Issues by Priority${NC}"
    echo "=================================="
    
    # Search issues
    local response=$(api_call GET "/search/issues?q=$(echo "$query" | jq -sRr @uri)&sort=created&order=desc&per_page=$count")
    
    # Parse and display by priority
    local p0s=$(echo "$response" | jq '.items[] | select(.labels[] | select(.name == "P0"))')
    local p1s=$(echo "$response" | jq '.items[] | select(.labels[] | select(.name == "P1"))')
    local p2s=$(echo "$response" | jq '.items[] | select(.labels[] | select(.name == "P2"))')
    local p3s=$(echo "$response" | jq '.items[] | select(.labels[] | select(.name == "P3"))')
    
    if [[ -n "$p0s" ]]; then
        echo -e "\n${RED}🔴 P0 (Critical)${NC}"
        echo "$p0s" | jq -r '"\(.number | tostring): \(.title)"' | head -n 10 | while IFS=':' read -r num title; do
            printf "  #%-4s %s\n" "$num" "$title"
        done
    fi
    
    if [[ -n "$p1s" ]]; then
        echo -e "\n${YELLOW}🟠 P1 (High)${NC}"
        echo "$p1s" | jq -r '"\(.number | tostring): \(.title)"' | head -n 10 | while IFS=':' read -r num title; do
            printf "  #%-4s %s\n" "$num" "$title"
        done
    fi
    
    if [[ -n "$p2s" ]]; then
        echo -e "\n${CYAN}🟡 P2 (Medium)${NC}"
        echo "$p2s" | jq -r '"\(.number | tostring): \(.title)"' | head -n 10 | while IFS=':' read -r num title; do
            printf "  #%-4s %s\n" "$num" "$title"
        done
    fi
    
    if [[ -n "$p3s" ]]; then
        echo -e "\n${GREEN}🟢 P3 (Low)${NC}"
        echo "$p3s" | jq -r '"\(.number | tostring): \(.title)"' | head -n 10 | while IFS=':' read -r num title; do
            printf "  #%-4s %s\n" "$num" "$title"
        done
    fi
}

get_next_issue() {
    echo -e "${CYAN}Getting next priority issue...${NC}"
    
    # Check P0 first
    for priority in P0 P1 P2 P3; do
        local query="repo:$REPO is:issue is:open label:$priority"
        local response=$(api_call GET "/search/issues?q=$(echo "$query" | jq -sRr @uri)&sort=created&order=asc&per_page=1")
        local issue=$(echo "$response" | jq '.items[0] // empty')
        
        if [[ -n "$issue" ]]; then
            local num=$(echo "$issue" | jq -r '.number')
            local title=$(echo "$issue" | jq -r '.title')
            local url=$(echo "$issue" | jq -r '.html_url')
            
            echo -e "${CYAN}Next Issue (Priority: $priority)${NC}"
            echo "  #$num: $title"
            echo "  URL: $url"
            return 0
        fi
    done
    
    echo -e "${YELLOW}⚠️ No open prioritized issues found${NC}"
}

set_priority() {
    local issue_num="$1"
    local new_priority="$2"
    
    if ! [[ "$new_priority" =~ ^P[0-3]$ ]]; then
        echo "❌ Invalid priority: $new_priority"
        exit 1
    fi
    
    echo "Setting priority for issue #$issue_num to $new_priority..."
    
    # Get current issue
    local issue=$(api_call GET "/repos/$REPO/issues/$issue_num")
    local current_labels=$(echo "$issue" | jq -r '.labels[].name')
    
    # Remove old priority labels
    local new_labels=()
    while IFS= read -r label; do
        if ! [[ "$label" =~ ^P[0-3]$ ]]; then
            new_labels+=("$label")
        fi
    done <<< "$current_labels"
    
    # Add new priority
    new_labels+=("$new_priority")
    
    # Update issue
    local payload=$(printf '%s\n' "${new_labels[@]}" | jq -R . | jq -s .)
    payload=$(echo "{\"labels\": $payload}" | jq .)
    
    api_call PATCH "/repos/$REPO/issues/$issue_num" "$payload" > /dev/null
    
    echo -e "${GREEN}✅ Issue #$issue_num updated to priority $new_priority${NC}"
}

priority_stats() {
    echo -e "${CYAN}Priority Distribution${NC}"
    echo "====================="
    
    for priority in P0 P1 P2 P3; do
        local query="repo:$REPO is:issue is:open label:$priority"
        local count=$(api_call GET "/search/issues?q=$(echo "$query" | jq -sRr @uri)" | jq '.total_count')
        echo "$priority: $count issues"
    done
    
    # Unprioritized
    local query="repo:$REPO is:issue is:open label:needs-priority"
    local uncount=$(api_call GET "/search/issues?q=$(echo "$query" | jq -sRr @uri)" | jq '.total_count')
    echo "Unprioritized: $uncount issues ⚠️"
}

# Main
check_token

case "${1:-list}" in
    create)
        shift
        title=""
        body=""
        priority="P1"
        labels=""
        assignee=""
        
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --title) title="$2"; shift 2 ;;
                --body) body="$2"; shift 2 ;;
                --priority) priority="$2"; shift 2 ;;
                --labels) labels="$2"; shift 2 ;;
                --assignee) assignee="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; print_usage; exit 1 ;;
            esac
        done
        
        if [[ -z "$title" ]]; then
            echo "❌ --title is required"
            exit 1
        fi
        
        create_issue "$title" "$body" "$priority" "$labels" "$assignee"
        ;;
        
    list)
        shift
        priority="all"
        state="open"
        count=10
        
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --priority) priority="$2"; shift 2 ;;
                --state) state="$2"; shift 2 ;;
                --count) count="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; print_usage; exit 1 ;;
            esac
        done
        
        list_issues "$priority" "$state" "$count"
        ;;
        
    next)
        get_next_issue
        ;;
        
    set-priority)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 set-priority <issue-number> <P0|P1|P2|P3>"
            exit 1
        fi
        set_priority "$2" "$3"
        ;;
        
    priority-stats)
        priority_stats
        ;;
        
    help|-h|--help)
        print_usage
        ;;
        
    *)
        echo "Unknown action: $1"
        print_usage
        exit 1
        ;;
esac
