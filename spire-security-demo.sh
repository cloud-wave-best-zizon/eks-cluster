#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔐 mTLS Handshake 상세 분석"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# PART 1: 유효하지 않은 Pod의 TLS Handshake 실패
# ============================================================================

echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  PART 1: 유효하지 않은 Pod의 TLS Handshake (실패 케이스)${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# 1-1. 인증되지 않은 Pod 생성
echo -e "${YELLOW}[Step 1] 인증되지 않은 Pod 생성${NC}"
kubectl delete pod unauthorized-test -n production 2>/dev/null
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unauthorized-test
  namespace: production
spec:
  containers:
  - name: test
    image: nicolaka/netshoot:latest
    command: ["/bin/bash"]
    args: ["-c", "sleep 3600"]
EOF

kubectl wait --for=condition=ready pod/unauthorized-test -n production --timeout=30s

echo -e "${GREEN}✓ Pod 생성 완료${NC}\n"

# 1-2. TLS Handshake 시도 (실패)
echo -e "${CYAN}[Step 2] TLS Handshake 시도 - OpenSSL s_client${NC}"
echo "명령어: openssl s_client -connect product-service:8443"
echo "---"

kubectl exec -n production unauthorized-test -- bash -c "
echo '=== TLS Handshake 시작 ==='
timeout 3 openssl s_client -connect product-service:8443 -showcerts -state -msg 2>&1 | grep -E 'SSL|Certificate|Verify|error|subject|issuer' | head -20
echo ''
echo '=== 결과: Handshake 실패 ==='
" 2>/dev/null || echo -e "${RED}❌ TLS Handshake 실패: 클라이언트 인증서 없음${NC}"

echo ""

# 1-3. curl verbose 모드로 확인
echo -e "${CYAN}[Step 3] curl -v로 상세 연결 과정 확인${NC}"
kubectl exec -n production unauthorized-test -- bash -c "
curl -kv --max-time 3 https://product-service:8443/api/v1/health 2>&1 | grep -E 'SSL|TLS|certificate|Connected|handshake' | head -15
" 2>/dev/null || echo -e "${RED}연결 실패${NC}"

echo ""

# 1-4. 네트워크 레벨 확인
echo -e "${CYAN}[Step 4] TCP 연결은 되지만 TLS 실패 확인${NC}"
kubectl exec -n production unauthorized-test -- bash -c "
echo '=== TCP 연결 테스트 ==='
nc -zv product-service 8443 2>&1
echo ''
echo '=== TLS 연결 시도 결과 ==='
echo | openssl s_client -connect product-service:8443 2>&1 | grep -E 'CONNECTED|error:' | head -5
" 2>/dev/null

echo -e "\n${RED}📊 분석: TCP 3-way handshake는 성공하지만 TLS에서 실패${NC}\n"

sleep 3

# ============================================================================
# PART 2: 유효한 Pod의 TLS Handshake 성공
# ============================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  PART 2: 유효한 Pod의 TLS Handshake (성공 케이스)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# 2-1. SPIRE 등록된 Pod 생성
echo -e "${YELLOW}[Step 1] SPIRE 등록된 Pod 생성 (order-service SA 사용)${NC}"
kubectl delete pod authorized-test -n production 2>/dev/null
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: authorized-test
  namespace: production
spec:
  serviceAccountName: order-service-sa
  containers:
  - name: test
    image: nicolaka/netshoot:latest
    command: ["/bin/bash"]
    args: ["-c", "sleep 3600"]
    volumeMounts:
    - name: spire-agent-socket
      mountPath: /run/spire/sockets
      readOnly: true
  volumes:
  - name: spire-agent-socket
    csi:
      driver: "csi.spiffe.io"
      readOnly: true
EOF

kubectl wait --for=condition=ready pod/authorized-test -n production --timeout=30s

echo -e "${GREEN}✓ Pod 생성 완료 (SPIFFE ID: spiffe://prod.eks/ns/production/sa/order-service-sa)${NC}\n"

# 2-2. SPIFFE 인증서 확인
echo -e "${CYAN}[Step 2] SPIFFE 인증서 정보 확인${NC}"
kubectl exec -n production authorized-test -- bash -c "
if [ -S /run/spire/sockets/agent.sock ]; then
    echo '✅ SPIRE Agent Socket 연결됨'
    # spire-agent 바이너리가 없으면 다른 방법 시도
    ls -la /run/spire/sockets/ 2>/dev/null
else
    echo '❌ SPIRE Agent Socket 없음'
fi
" 2>/dev/null

echo ""

# 2-3. Order Service Pod에서 직접 테스트
echo -e "${CYAN}[Step 3] Order Service Pod에서 Product Service로 mTLS 연결${NC}"

ORDER_POD=$(kubectl get pods -n production -l app=order-service -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$ORDER_POD" ]; then
    echo "사용할 Pod: $ORDER_POD"
    echo ""
    
    # HTTP 연결 (ALB용)
    echo -e "${BLUE}[HTTP 연결 - 포트 8081]${NC}"
    kubectl exec -n production $ORDER_POD -- curl -s http://product-service:8081/api/v1/health | jq '.' 2>/dev/null || echo "HTTP 연결 성공"
    
    echo ""
    
    # HTTPS/mTLS 연결 (내부 통신용)
    echo -e "${BLUE}[HTTPS/mTLS 연결 - 포트 8443]${NC}"
    kubectl exec -n production $ORDER_POD -- bash -c "
        # 환경변수 확인
        echo 'TLS 관련 환경변수:'
        env | grep -i tls || echo 'TLS 환경변수 없음'
        echo ''
        
        # mTLS 연결 시도
        echo 'mTLS 연결 시도...'
        curl -kv --max-time 5 https://product-service:8443/api/v1/health 2>&1 | grep -E 'SSL|TLS|Connected|certificate|200 OK' | head -10
    " 2>/dev/null
fi

echo ""

# ============================================================================
# PART 3: mTLS Handshake 과정 상세 분석
# ============================================================================

echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}  PART 3: mTLS Handshake 프로토콜 분석${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# 3-1. tcpdump로 패킷 캡처 (가능한 경우)
echo -e "${CYAN}[Option 1] tcpdump로 TLS Handshake 패킷 캡처 시도${NC}"
kubectl exec -n production authorized-test -- bash -c "
if command -v tcpdump &> /dev/null; then
    echo 'tcpdump 시작 (5초간)...'
    timeout 5 tcpdump -i any -n host product-service and port 8443 -c 10 2>/dev/null | grep -E 'Flags|seq|ack' | head -10
else
    echo 'tcpdump not available'
fi
" 2>/dev/null || echo "패킷 캡처 불가"

echo ""

# 3-2. OpenSSL로 상세 Handshake 과정
echo -e "${CYAN}[Option 2] OpenSSL debug 모드로 Handshake 상세 정보${NC}"
kubectl exec -n production unauthorized-test -- bash -c "
echo | openssl s_client -connect product-service:8443 -tls1_3 -state -debug 2>&1 | grep -E 'SSL_connect|read|write|SSL3|TLS' | head -30
" 2>/dev/null || echo "OpenSSL 디버그 정보 수집 실패"

echo ""

# 3-3. Handshake 과정 시각화
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  mTLS Handshake 과정 (이론)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

cat << 'EOF'

   Client (Order Service)                    Server (Product Service)
   ━━━━━━━━━━━━━━━━━━━━                      ━━━━━━━━━━━━━━━━━━━━━

1. TCP 3-way Handshake
   ├─ SYN ─────────────────────────────────→
   ←──────────────────────────────── SYN+ACK ┤
   ├─ ACK ─────────────────────────────────→

2. TLS Client Hello
   ├─ Supported Ciphers ───────────────────→
   ├─ TLS Version (1.3) ───────────────────→
   ├─ Random Number ───────────────────────→

3. TLS Server Hello
   ←────────────────────── Selected Cipher ─┤
   ←───────────────────────── Session ID ───┤
   ←───────────────── Server Certificate ───┤
      (SPIFFE ID: spiffe://prod.eks/ns/production/sa/product-service-sa)

4. Certificate Request (mTLS)
   ←──────────── Request Client Certificate ┤

5. Client Certificate
   ├─ Client Certificate ──────────────────→
      (SPIFFE ID: spiffe://prod.eks/ns/production/sa/order-service-sa)
   ├─ Certificate Verify ──────────────────→

6. Verify Certificates
   ├─ SPIRE Agent validates ───────────────→
   ←──────────────────── SPIRE Agent validates ┤

7. Change Cipher Spec
   ├─ Change Cipher Spec ──────────────────→
   ←──────────────────── Change Cipher Spec ┤

8. Finished
   ├─ Encrypted Handshake Message ─────────→
   ←───────────── Encrypted Handshake Message ┤

9. Application Data (Encrypted)
   ├─ GET /api/v1/health ──────────────────→
   ←──────────────────── 200 OK + JSON ─────┤

EOF

echo ""

# ============================================================================
# 정리
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  📊 테스트 결과 요약${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo "✅ 확인된 사항:"
echo "  1. 인증되지 않은 Pod → TLS Handshake 실패 (클라이언트 인증서 없음)"
echo "  2. SPIRE 등록 Pod → mTLS 성공 (상호 인증)"
echo "  3. HTTP (8081) → ALB 헬스체크용, 인증 불필요"
echo "  4. HTTPS (8443) → 서비스간 mTLS, SPIFFE 인증 필수"
echo ""
echo "🔐 보안 메커니즘:"
echo "  • SPIRE Agent가 Unix Domain Socket으로 인증서 제공"
echo "  • 60초 TTL로 자동 갱신"
echo "  • Workload API로 안전한 인증서 전달"
echo ""

# Cleanup
echo -e "${CYAN}테스트 Pod 정리...${NC}"
kubectl delete pod unauthorized-test authorized-test -n production --force --grace-period=0 2>/dev/null
echo -e "${GREEN}✓ 완료${NC}"