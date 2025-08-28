#!/bin/bash

set -euo pipefail

# Parse command line arguments
APP_NAMES=()
NAMESPACE="ml-ops"
REFRESH_INTERVAL="10"

# Process arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--refresh)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            print_usage
            exit 1
            ;;
        *)
            APP_NAMES+=("$1")
            shift
            ;;
    esac
done

# Set default app name if none provided
if [ ${#APP_NAMES[@]} -eq 0 ]; then
    APP_NAMES=("mlflow")
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    local title="$1"
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}$(printf "%98s" "$title" | sed 's/.*/  & /')${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
}

print_subheader() {
    local title="$1"
    local emoji="$2"
    echo
    echo -e "${YELLOW}${emoji} ${BOLD}${title}${NC}"
    echo -e "${YELLOW}$(printf '%.50s' "$(yes '─' | head -50 | tr -d '\n')")${NC}"
}

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

format_status() {
    local status="$1"
    case "$status" in
        "Running"|"Ready"|"True"|"Available")
            echo -e "${GREEN}✅ $status${NC}"
            ;;
        "Pending"|"ContainerCreating")
            echo -e "${YELLOW}⏳ $status${NC}"
            ;;
        "Failed"|"Error"|"CrashLoopBackOff"|"ImagePullBackOff"|"False")
            echo -e "${RED}❌ $status${NC}"
            ;;
        *)
            echo -e "${WHITE}🔄 $status${NC}"
            ;;
    esac
}

format_number() {
    local num="$1"
    local context="$2"
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        if [ "$num" -eq 0 ] && [ "$context" = "restarts" ]; then
            echo -e "${GREEN}$num${NC}"
        elif [ "$num" -gt 0 ] && [ "$context" = "restarts" ]; then
            echo -e "${YELLOW}$num${NC}"
        else
            echo -e "${CYAN}$num${NC}"
        fi
    else
        echo "$num"
    fi
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not in PATH"
        exit 1
    fi
}

check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "Error: Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
}

monitor_deployments() {
    print_subheader "DEPLOYMENTS" "🚀"
    local found_any=false
    echo -e "${WHITE}NAME${NC}\t\t${WHITE}READY${NC}\t${WHITE}UP-TO-DATE${NC}\t${WHITE}AVAILABLE${NC}\t${WHITE}AGE${NC}\t${WHITE}APP${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local deployments
        if deployments=$(kubectl get deployments -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null) && [ -n "$deployments" ]; then
            found_any=true
            echo "$deployments" | while read -r name ready uptodate available age; do
                echo -e "${CYAN}$name${NC}\t\t$(format_status "$ready")\t$(format_number "$uptodate" "")\t\t$(format_status "$available")\t\t${PURPLE}$age${NC}\t\t${YELLOW}$APP_NAME${NC}"
            done
        else
            deployments=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME " || echo "")
            if [ -n "$deployments" ]; then
                found_any=true
                echo "$deployments" | while read -r name ready uptodate available age; do
                    echo -e "${CYAN}$name${NC}\t\t$(format_status "$ready")\t$(format_number "$uptodate" "")\t\t$(format_status "$available")\t\t${PURPLE}$age${NC}\t\t${YELLOW}$APP_NAME${NC}"
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No deployments found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_replicasets() {
    print_subheader "REPLICASETS" "🔄"
    local found_any=false
    echo -e "${WHITE}NAME${NC}\t\t\t${WHITE}DESIRED${NC}\t${WHITE}CURRENT${NC}\t${WHITE}READY${NC}\t${WHITE}AGE${NC}\t${WHITE}APP${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local replicasets
        if replicasets=$(kubectl get replicasets -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null) && [ -n "$replicasets" ]; then
            found_any=true
            echo "$replicasets" | while read -r name desired current ready age; do
                echo -e "${CYAN}$name${NC}\t$(format_number "$desired" "")\t$(format_number "$current" "")\t$(format_number "$ready" "")\t${PURPLE}$age${NC}\t${YELLOW}$APP_NAME${NC}"
            done
        else
            replicasets=$(kubectl get replicasets -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME-" | grep -v "^$APP_NAME-[^-]*-" || echo "")
            if [ -n "$replicasets" ]; then
                found_any=true
                echo "$replicasets" | while read -r name desired current ready age; do
                    echo -e "${CYAN}$name${NC}\t$(format_number "$desired" "")\t$(format_number "$current" "")\t$(format_number "$ready" "")\t${PURPLE}$age${NC}\t${YELLOW}$APP_NAME${NC}"
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No replicasets found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_pods() {
    print_subheader "PODS" "🐳"
    local found_any=false
    echo -e "${WHITE}NAME${NC}\t\t\t${WHITE}STATUS${NC}\t\t${WHITE}RESTARTS${NC}\t${WHITE}AGE${NC}\t${WHITE}NODE${NC}\t${WHITE}APP${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local pods
        if pods=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null) && [ -n "$pods" ]; then
            found_any=true
            kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" --no-headers -o wide | while read -r name ready status restarts age ip node nominated readiness; do
                echo -e "${CYAN}$name${NC}\t$(format_status "$status")\t$(format_number "$restarts" "restarts")\t\t${PURPLE}$age${NC}\t${BLUE}$node${NC}\t${YELLOW}$APP_NAME${NC}"
            done
        else
            pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME-" | grep -v "^$APP_NAME-[a-z]" || echo "")
            if [ -n "$pods" ]; then
                found_any=true
                echo "$pods" | while read -r name ready status restarts age ip node nominated readiness; do
                    echo -e "${CYAN}$name${NC}\t$(format_status "$status")\t$(format_number "$restarts" "restarts")\t\t${PURPLE}$age${NC}\t${BLUE}$node${NC}\t${YELLOW}$APP_NAME${NC}"
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No pods found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_services() {
    print_subheader "SERVICES" "🌐"
    local found_any=false
    echo -e "${WHITE}NAME${NC}\t\t${WHITE}TYPE${NC}\t\t${WHITE}CLUSTER-IP${NC}\t${WHITE}EXTERNAL-IP${NC}\t${WHITE}PORT(S)${NC}\t\t${WHITE}AGE${NC}\t${WHITE}APP${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local services
        if services=$(kubectl get services -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null) && [ -n "$services" ]; then
            found_any=true
            echo "$services" | while read -r name type cluster_ip external_ip ports age; do
                echo -e "${CYAN}$name${NC}\t\t${YELLOW}$type${NC}\t\t${BLUE}$cluster_ip${NC}\t${GREEN}$external_ip${NC}\t\t${PURPLE}$ports${NC}\t$age\t${YELLOW}$APP_NAME${NC}"
            done
        else
            services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | awk -v app="$APP_NAME" '$1 == app {print}' || echo "")
            if [ -n "$services" ]; then
                found_any=true
                echo "$services" | while read -r name type cluster_ip external_ip ports age; do
                    echo -e "${CYAN}$name${NC}\t\t${YELLOW}$type${NC}\t\t${BLUE}$cluster_ip${NC}\t${GREEN}$external_ip${NC}\t\t${PURPLE}$ports${NC}\t$age\t${YELLOW}$APP_NAME${NC}"
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No services found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_pod_health() {
    print_subheader "POD HEALTH STATUS" "💊"
    local found_any=false
    echo -e "${WHITE}POD NAME${NC}\t\t\t${WHITE}PHASE${NC}\t\t${WHITE}READY${NC}\t${WHITE}RESTARTS${NC}\t${WHITE}APP${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local pod_names
        if pod_names=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) && [ -n "$pod_names" ]; then
            found_any=true
            for pod in $pod_names; do
                local phase ready restarts
                phase=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                ready=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                restarts=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
                echo -e "${CYAN}$pod${NC}\t$(format_status "$phase")\t$(format_status "$ready")\t$(format_number "$restarts" "restarts")\t${YELLOW}$APP_NAME${NC}"
            done
        else
            pod_names=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME-" | grep -v "^$APP_NAME-[a-z]" | awk '{print $1}' || echo "")
            if [ -n "$pod_names" ]; then
                found_any=true
                for pod in $pod_names; do
                    local phase ready restarts
                    phase=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                    ready=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                    restarts=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
                    echo -e "${CYAN}$pod${NC}\t$(format_status "$phase")\t$(format_status "$ready")\t$(format_number "$restarts" "restarts")\t${YELLOW}$APP_NAME${NC}"
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No pods found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_events() {
    print_subheader "RECENT EVENTS" "📋"
    local found_any=false
    echo -e "${WHITE}LAST SEEN${NC}\t${WHITE}TYPE${NC}\t\t${WHITE}REASON${NC}\t\t${WHITE}OBJECT${NC}\t\t${WHITE}MESSAGE${NC}"
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local events
        events=$(kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | grep "$APP_NAME" | grep -v "$APP_NAME-[a-z]" | tail -n 5 | head -n 5 || echo "")
        if [ -n "$events" ]; then
            found_any=true
            echo "$events" | while IFS= read -r line; do
                if [[ "$line" =~ Normal ]]; then
                    echo -e "${GREEN}$line${NC}"
                elif [[ "$line" =~ Warning ]]; then
                    echo -e "${YELLOW}$line${NC}"
                else
                    echo -e "${WHITE}$line${NC}"
                fi
            done
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${BLUE}ℹ️  No recent events found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_pod_logs() {
    print_subheader "POD LOGS" "📄"
    local found_any=false
    
    for APP_NAME in "${APP_NAMES[@]}"; do
        local pod_names
        if pod_names=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) && [ -n "$pod_names" ]; then
            found_any=true
            for pod in $pod_names; do
                echo
                echo -e "${PURPLE}🔍 Logs for pod: ${BOLD}$pod${NC} ${YELLOW}(app: $APP_NAME)${NC}"
                echo -e "${YELLOW}$(printf '%.60s' "$(yes '─' | head -60 | tr -d '\n')")${NC}"
                local logs
                logs=$(kubectl logs "$pod" -n "$NAMESPACE" --tail=10 2>/dev/null || echo "Unable to fetch logs")
                if [[ "$logs" == "Unable to fetch logs" ]]; then
                    echo -e "${RED}❌ Unable to fetch logs for pod: $pod${NC}"
                else
                    echo -e "${WHITE}$logs${NC}"
                fi
            done
        else
            pod_names=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME-" | grep -v "^$APP_NAME-[a-z]" | awk '{print $1}' || echo "")
            if [ -n "$pod_names" ]; then
                found_any=true
                for pod in $pod_names; do
                    echo
                    echo -e "${PURPLE}🔍 Logs for pod: ${BOLD}$pod${NC} ${YELLOW}(app: $APP_NAME)${NC}"
                    echo -e "${YELLOW}$(printf '%.60s' "$(yes '─' | head -60 | tr -d '\n')")${NC}"
                    local logs
                    logs=$(kubectl logs "$pod" -n "$NAMESPACE" --tail=10 2>/dev/null || echo "Unable to fetch logs")
                    if [[ "$logs" == "Unable to fetch logs" ]]; then
                        echo -e "${RED}❌ Unable to fetch logs for pod: $pod${NC}"
                    else
                        echo -e "${WHITE}$logs${NC}"
                    fi
                done
            fi
        fi
    done
    
    if [ "$found_any" = false ]; then
        echo -e "${RED}❌ No pods found for apps: ${BOLD}${APP_NAMES[*]}${NC}"
    fi
}

monitor_ingress() {
    print_subheader "INGRESS"
    if kubectl get ingress -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null | grep -q .; then
        kubectl get ingress -n "$NAMESPACE" -l app="$APP_NAME" -o wide
    else
        kubectl get ingress -n "$NAMESPACE" | awk -v app="$APP_NAME" '$1 == app {print}' || echo "No ingress found for app: $APP_NAME"
    fi
}

monitor_configmaps_secrets() {
    print_subheader "CONFIGMAPS & SECRETS"
    echo "ConfigMaps:"
    if kubectl get configmaps -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null | grep -q .; then
        kubectl get configmaps -n "$NAMESPACE" -l app="$APP_NAME"
    else
        kubectl get configmaps -n "$NAMESPACE" | awk -v app="$APP_NAME" '$1 == app {print}' || echo "No configmaps found for app: $APP_NAME"
    fi
    
    echo
    echo "Secrets:"
    if kubectl get secrets -n "$NAMESPACE" -l app="$APP_NAME" --no-headers 2>/dev/null | grep -q .; then
        kubectl get secrets -n "$NAMESPACE" -l app="$APP_NAME"
    else
        kubectl get secrets -n "$NAMESPACE" | awk -v app="$APP_NAME" '$1 == app {print}' || echo "No secrets found for app: $APP_NAME"
    fi
}

monitor_resource_usage() {
    print_subheader "RESOURCE USAGE"
    echo "Pod Resource Usage:"
    if kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^$APP_NAME-" | grep -v "^$APP_NAME-[a-z]"; then
        echo "Resource metrics available"
    else
        echo "Resource metrics not available (metrics-server may not be installed)"
    fi
}

print_usage() {
    echo "Usage: $0 [OPTIONS] [APP_NAME1] [APP_NAME2] ..."
    echo ""
    echo "Options:"
    echo "  -n, --namespace NAMESPACE    Kubernetes namespace (default: ml-ops)"
    echo "  -r, --refresh INTERVAL       Refresh interval in seconds (default: 10)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Arguments:"
    echo "  APP_NAME                     Application name(s) to monitor (default: mlflow)"
    echo "                               Multiple app names can be specified"
    echo ""
    echo "Examples:"
    echo "  $0 mlflow                           # Monitor single app 'mlflow'"
    echo "  $0 mlflow grafana prometheus        # Monitor multiple apps"
    echo "  $0 -n production app1 app2          # Monitor apps in 'production' namespace"
    echo "  $0 -r 5 -n staging myapp            # Custom refresh interval and namespace"
    echo ""
    echo "Press Ctrl+C to stop monitoring"
}

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi


    check_kubectl
    check_namespace
    
    echo "Starting Kubernetes Application Monitor"
    echo "Apps: ${APP_NAMES[*]} | Namespace: $NAMESPACE | Refresh: ${REFRESH_INTERVAL}s"
    echo "Press Ctrl+C to stop..."
    
    trap 'echo -e "\n\nMonitoring stopped."; exit 0' INT TERM
    
    while true; do
        clear
        print_header "🔍 KUBERNETES APPLICATION MONITOR - $(get_timestamp) 🔍"
        echo -e "${BOLD}${GREEN}🚀 Applications: ${CYAN}${APP_NAMES[*]}${NC} ${BOLD}${BLUE}| 🎯 Namespace: ${CYAN}$NAMESPACE${NC} ${BOLD}${PURPLE}| ⏱️  Refresh: ${CYAN}${REFRESH_INTERVAL}s${NC}"
        
        monitor_deployments
        monitor_pods
        monitor_services
        monitor_pod_health
        monitor_events
        monitor_pod_logs
        
        print_header "⏱️  Next refresh in ${REFRESH_INTERVAL} seconds... (Press Ctrl+C to stop)"
        sleep "$REFRESH_INTERVAL"
    done
}

main "$@"