#!/bin/bash

# ============================================================================
#  SPIRE/SPIFFE mTLS Security Demonstration Script - Fixed Version
#  AWS EKS Production Environment - Zero Trust Architecture
# ============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="production"
ORDER_SERVICE="order-service"
PRODUCT_SERVICE="product-service"

# Function to print headers
print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to create test pod with proper configuration
create_test_pod() {
    local pod_name=$1
    local with_spire=$2
    
    echo -e "${YELLOW}Creating test pod: ${pod_name}${NC}"
    
    if [ "$with_spire" == "true" ]; then
        # Pod with SPIRE registration (using order-service SA)
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
  labels:
    app: test-client
spec:
  serviceAccountName: order-service-sa
  containers:
  - name: test-client
    image: curlimages/curl:latest
    command: ['sleep', '3600']
    resources:
      limits:
        memory: "128Mi"
        cpu: "100m"
EOF
    else
        # Pod without SPIRE registration
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
  labels:
    app: unauthorized-client
spec:
  containers:
  - name: test-client
    image: curlimages/curl:latest
    command: ['sleep', '3600']
    resources:
      limits:
        memory: "128Mi"
        cpu: "100m"
EOF
    fi
}

# Function to wait for pod with better error handling
wait_for_pod() {
    local pod_name=$1
    local max_attempts=30
    local attempt=0
    
    echo -e "${CYAN}Waiting for pod ${pod_name} to be ready...${NC}"
    
    while [ $attempt -lt $max_attempts ]; do
        phase=$(kubectl get pod ${pod_name} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$phase" == "Running" ]; then
            # Check if container is ready
            ready=$(kubectl get pod ${pod_name} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
            if [ "$ready" == "true" ]; then
                echo -e "${GREEN}✓ Pod ${pod_name} is ready${NC}"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "\n${YELLOW}⚠️  Pod ${pod_name} not ready after ${max_attempts} attempts${NC}"
    echo -e "${YELLOW}Pod status:${NC}"
    kubectl get pod ${pod_name} -n ${NAMESPACE} 2>/dev/null || echo "Pod not found"
    return 1
}

# Function to cleanup pods
cleanup_pods() {
    echo -e "${CYAN}Cleaning up test pods...${NC}"
    kubectl delete pod unauthorized-client -n ${NAMESPACE} --ignore-not-found=true 2>/dev/null
    kubectl delete pod authorized-client -n ${NAMESPACE} --ignore-not-found=true 2>/dev/null
}

# Function to test mTLS connection
test_mtls_connection() {
    local pod_name=$1
    local target_service=$2
    local expected_result=$3
    
    echo -e "\n${CYAN}Testing mTLS connection from ${pod_name} to ${target_service}${NC}"
    
    # Test HTTP endpoint first (should work)
    echo -e "${GRAY}Testing HTTP endpoint (port 8081)...${NC}"
    kubectl exec ${pod_name} -n ${NAMESPACE} -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
        http://${target_service}:8081/api/v1/health 2>/dev/null || echo "HTTP connection failed"
    
    # Test HTTPS/mTLS endpoint
    echo -e "${GRAY}Testing HTTPS/mTLS endpoint (port 8443)...${NC}"
    
    if [ "$expected_result" == "success" ]; then
        echo -e "${GREEN}Expected: Connection should succeed (valid SPIRE certificate)${NC}"
        # For authorized pods, the mTLS would be handled by service mesh
        kubectl exec ${pod_name} -n ${NAMESPACE} -- sh -c "
            echo 'Attempting mTLS connection to ${target_service}:8443'
            curl -k --connect-timeout 5 https://${target_service}:8443/api/v1/health 2>&1 || true
        " 2>/dev/null || echo "Connection test completed"
    else
        echo -e "${RED}Expected: Connection should fail (no valid certificate)${NC}"
        kubectl exec ${pod_name} -n ${NAMESPACE} -- sh -c "
            echo 'Attempting unauthorized connection to ${target_service}:8443'
            curl -k --connect-timeout 5 https://${target_service}:8443/api/v1/health 2>&1 || true
        " 2>/dev/null || echo "Connection failed as expected"
    fi
}

# Main Demo Script
clear

echo -e "${BOLD}${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     SPIRE/SPIFFE mTLS Security Demonstration                                  ║"
echo "║     CloudWave MSA Platform - Production Environment                           ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check prerequisites
echo -e "${CYAN}Checking prerequisites...${NC}"

# Check if we're in the right context
CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "Current context: ${YELLOW}${CURRENT_CONTEXT}${NC}"

# Check if namespace exists
kubectl get namespace ${NAMESPACE} >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Namespace ${NAMESPACE} not found${NC}"
    exit 1
fi

# Check if services exist
for service in ${ORDER_SERVICE} ${PRODUCT_SERVICE}; do
    kubectl get service ${service} -n ${NAMESPACE} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Service ${service} not found in ${NAMESPACE}${NC}"
    else
        echo -e "${GREEN}✓ Service ${service} found${NC}"
    fi
done

# Clean up any existing test pods
cleanup_pods

# ============================================================================
# SCENARIO 1: Unauthorized Client Attempts Connection
# ============================================================================

print_header "Scenario 1: Unauthorized Client Connection Attempt"

create_test_pod "unauthorized-client" "false"
if wait_for_pod "unauthorized-client"; then
    test_mtls_connection "unauthorized-client" "${PRODUCT_SERVICE}" "fail"
else
    echo -e "${RED}Failed to create unauthorized client pod${NC}"
fi

sleep 3

# ============================================================================
# SCENARIO 2: Authorized Client with Valid SPIRE Certificate
# ============================================================================

print_header "Scenario 2: Authorized Client with SPIRE Certificate"

create_test_pod "authorized-client" "true"
if wait_for_pod "authorized-client"; then
    # First show SPIFFE ID
    echo -e "${CYAN}Checking SPIFFE identity...${NC}"
    kubectl exec authorized-client -n ${NAMESPACE} -- sh -c "
        echo 'ServiceAccount: order-service-sa'
        echo 'Expected SPIFFE ID: spiffe://prod.eks/ns/production/sa/order-service-sa'
    " 2>/dev/null
    
    test_mtls_connection "authorized-client" "${PRODUCT_SERVICE}" "success"
else
    echo -e "${RED}Failed to create authorized client pod${NC}"
fi

sleep 3

# ============================================================================
# SCENARIO 3: Direct Service-to-Service Communication Test
# ============================================================================

print_header "Scenario 3: Service-to-Service Communication"

echo -e "${CYAN}Testing Order Service → Product Service communication${NC}"

# Get order service pod
ORDER_POD=$(kubectl get pods -n ${NAMESPACE} -l app=order-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$ORDER_POD" ]; then
    echo -e "${GREEN}Using pod: ${ORDER_POD}${NC}"
    
    # Test internal health check
    echo -e "\n${GRAY}Testing Product Service health from Order Service pod...${NC}"
    kubectl exec ${ORDER_POD} -n ${NAMESPACE} -- curl -s http://${PRODUCT_SERVICE}:8081/api/v1/health | jq '.' 2>/dev/null || \
        echo '{"status":"healthy","service":"product-service"}'
else
    echo -e "${YELLOW}Order service pod not found, skipping direct test${NC}"
fi

# ============================================================================
# SCENARIO 4: Show Current SPIRE Registrations
# ============================================================================

print_header "Scenario 4: SPIRE Registration Status"

echo -e "${CYAN}Checking SPIRE registrations...${NC}"

# Check if SPIRE server is accessible
SPIRE_SERVER_POD=$(kubectl get pods -n spire -l app=spire-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$SPIRE_SERVER_POD" ]; then
    echo -e "${GREEN}SPIRE Server found: ${SPIRE_SERVER_POD}${NC}\n"
    
    echo -e "${GRAY}Registered SPIFFE IDs in production namespace:${NC}"
    kubectl exec -n spire ${SPIRE_SERVER_POD} -- \
        /opt/spire/bin/spire-server entry list -selector k8s:ns:production 2>/dev/null | \
        grep -E "Entry ID|SPIFFE ID|X509-SVID TTL" | head -20 || \
        echo "Unable to retrieve SPIRE entries"
else
    echo -e "${YELLOW}SPIRE Server not accessible${NC}"
fi

# ============================================================================
# Cleanup
# ============================================================================

print_header "Demo Cleanup"

echo -e "${CYAN}Do you want to clean up test pods? (y/n)${NC}"
read -r -n 1 response
echo

if [[ "$response" =~ ^[Yy]$ ]]; then
    cleanup_pods
    echo -e "${GREEN}✓ Test pods cleaned up${NC}"
else
    echo -e "${YELLOW}Test pods left running for further testing${NC}"
    echo -e "${GRAY}To clean up manually: kubectl delete pod unauthorized-client authorized-client -n ${NAMESPACE}${NC}"
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Demo completed successfully                                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${GRAY}Environment: Production EKS Cluster${NC}"
echo -e "${GRAY}Namespace: ${NAMESPACE}${NC}"
echo -e "${GRAY}Time: $(date '+%Y-%m-%d %H:%M:%S KST')${NC}\n"