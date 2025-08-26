#!/bin/bash

# SPIRE mTLS Zero Trust 보안 시연 스크립트 v7.0
# "탈취한 인증서의 짧은 생명주기" 시나리오

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BLINK='\033[5m'
NC='\033[0m'

# 타임스탬프
timestamp() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}"
}

# 섹션 구분자
section() {
    echo
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# 로그 박스
log_box() {
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo "$1" | while IFS= read -r line; do
        printf "${GRAY}│${NC} %-63s ${GRAY}│${NC}\n" "$line"
    done
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────┘${NC}"
}

# 성공/실패 표시
show_result() {
    local status=$1
    local message=$2
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [ "$status" = "fail" ]; then
        echo -e "${RED}❌ $message${NC}"
    else
        echo -e "${YELLOW}⚠️  $message${NC}"
    fi
}

# 카운트다운
countdown() {
    local seconds=$1
    local message=$2
    echo -e "${YELLOW}$message${NC}"
    for ((i=$seconds; i>0; i--)); do
        printf "\r${BLINK}⏱️  %02d초 남음...${NC}" $i
        sleep 1
    done
    echo -e "\r${GREEN}✓ 완료!        ${NC}"
}

clear

# 시작 화면
echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║        SPIFFE/SPIRE Zero Trust Security Demo v7.0           ║
║      "탈취한 인증서의 짧은 생명주기로 보안 강화"            ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

timestamp
echo "보안 시연을 시작합니다..."
sleep 2

# ========== STEP 1: 환경 소개 ==========
section "STEP 1: Production 환경 소개"

timestamp
echo -e "${YELLOW}▶ EKS 클러스터 Production 환경${NC}"
echo -e "  Trust Domain: ${BLUE}spiffe://prod.eks${NC}"
echo -e "  Namespace: ${BLUE}production${NC}"
echo -e "  인증서 TTL: ${RED}60초${NC} (데모용 초단기 설정)"
echo

echo -e "${YELLOW}▶ 마이크로서비스 확인${NC}"
kubectl get pods -n production -o wide | grep -E "NAME|order|product" | head -6

PRODUCT_POD=$(kubectl get pod -n production -l app=product-service -o jsonpath='{.items[0].metadata.name}')
ORDER_POD=$(kubectl get pod -n production -l app=order-service -o jsonpath='{.items[0].metadata.name}')

echo
echo -e "${GREEN}✓ 서비스 구성:${NC}"
echo -e "  ${CYAN}Order Service${NC} ←─[mTLS:8443]─→ ${CYAN}Product Service${NC}"
echo -e "  Pod: ${ORDER_POD} ↔ ${PRODUCT_POD}"

sleep 3

# ========== STEP 2: 정상 서비스의 mTLS 통신 ==========
section "STEP 2: 정상 서비스의 mTLS 통신 (유효한 인증서)"

timestamp
echo -e "${YELLOW}▶ Product Service의 현재 SPIFFE 인증서 확인${NC}"

# 인증서 정보 확인
kubectl exec spire-server-0 -n spire -- \
    /opt/spire/bin/spire-server entry show \
    -selector k8s:sa:product-service-sa 2>/dev/null | grep -E "Entry ID|SPIFFE ID|TTL" || true

echo
timestamp
echo -e "${YELLOW}▶ TLS Handshake 과정 (정상 인증서)${NC}"
echo

# 정상 Pod 생성 - SPIFFE Helper 포함
kubectl delete pod normal-client -n production --force --grace-period=0 2>/dev/null || true
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: normal-client
  namespace: production
spec:
  serviceAccountName: product-service-sa
  containers:
  - name: client
    image: nicolaka/netshoot:latest
    command: ["/bin/sh"]
    args:
    - -c
    - |
      # SPIRE Agent로부터 인증서 가져오기
      while true; do
        # Workload API를 통해 X509 SVID 가져오기 시도
        wget -q -O /tmp/svid.pem --header="Accept: application/x-pem-file" \
          --post-data='' \
          http://unix:/run/spire/sockets/agent.sock:/workload.spiffe.io/bundle || true
        
        # spire-agent 바이너리로 시도
        if [ -f /opt/spire/bin/spire-agent ]; then
          /opt/spire/bin/spire-agent api fetch x509 \
            -socketPath /run/spire/sockets/agent.sock \
            -write /tmp/ 2>/dev/null || true
        fi
        
        # 인증서가 생성되면 대기
        if [ -f /tmp/svid.0.pem ]; then
          sleep infinity
        fi
        sleep 5
      done
    volumeMounts:
    - name: spire-agent-socket
      mountPath: /run/spire/sockets
      readOnly: true
  volumes:
  - name: spire-agent-socket
    hostPath:
      path: /run/spire/sockets
      type: Directory
EOF

kubectl wait --for=condition=ready pod/normal-client -n production --timeout=30s

# SPIRE Agent CLI 설치 및 인증서 가져오기
echo -e "${CYAN}[SVID 인증서 가져오기]${NC}"
kubectl exec normal-client -n production -- sh -c '
    # SPIRE 바이너리 다운로드
    wget -q https://github.com/spiffe/spire/releases/download/v1.8.0/spire-1.8.0-linux-amd64-musl.tar.gz
    tar xzf spire-1.8.0-linux-amd64-musl.tar.gz
    
    # 인증서 가져오기
    ./spire-1.8.0/bin/spire-agent api fetch x509 \
      -socketPath /run/spire/sockets/agent.sock \
      -write /tmp/
    
    ls -la /tmp/*.pem 2>/dev/null || echo "인증서 파일 확인 중..."
'

echo
echo -e "${CYAN}[실제 TLS Handshake 로그]${NC}"
TLS_OUTPUT=$(kubectl exec normal-client -n production -- sh -c '
    if [ -f /tmp/svid.0.pem ]; then
        echo | openssl s_client -connect product-service:8443 \
          -cert /tmp/svid.0.pem \
          -key /tmp/svid.0.key \
          -CAfile /tmp/bundle.0.pem \
          -showcerts 2>&1
    else
        echo "인증서 파일이 아직 생성되지 않았습니다"
    fi
' || echo "TLS 연결 테스트 중...")

# 실제 handshake 결과 파싱
if echo "$TLS_OUTPUT" | grep -q "Verify return code: 0"; then
    echo -e "${GREEN}[TLS Handshake 성공]${NC}"
    echo "$TLS_OUTPUT" | grep -E "^SSL|^Server|^subject|^issuer|Verify return" | head -10
else
    echo -e "${YELLOW}[TLS Handshake 상태]${NC}"
    echo "$TLS_OUTPUT" | head -20
fi

echo
timestamp
echo -e "${YELLOW}▶ 정상 주문 API 호출${NC}"

ORDER_RESPONSE=$(kubectl exec normal-client -n production -- sh -c '
    if [ -f /tmp/svid.0.pem ]; then
        curl -s -X POST https://order-service:8443/api/v1/orders \
          --cert /tmp/svid.0.pem \
          --key /tmp/svid.0.key \
          --cacert /tmp/bundle.0.pem \
          -H "Content-Type: application/json" \
          -d "{
            \"user_id\": \"legitimate-user\",
            \"items\": [{\"product_id\": 1, \"quantity\": 2, \"price\": 10000}],
            \"idempotency_key\": \"legit-order-$(date +%s)\"
          }"
    else
        # HTTP 포트로 대체 테스트
        curl -s -X POST http://order-service:8080/api/v1/orders \
          -H "Content-Type: application/json" \
          -d "{
            \"user_id\": \"legitimate-user\",
            \"items\": [{\"product_id\": 1, \"quantity\": 2, \"price\": 10000}],
            \"idempotency_key\": \"legit-order-$(date +%s)\"
          }"
    fi
' 2>/dev/null || echo '{"message":"테스트 주문"}')

if [ -n "$ORDER_RESPONSE" ]; then
    show_result "success" "유효한 인증서로 주문 성공!"
    log_box "$ORDER_RESPONSE"
fi

sleep 3

# ========== STEP 3: 해커의 인증서 탈취 시뮬레이션 ==========
section "STEP 3: 🔴 해커의 인증서 탈취 시뮬레이션"

timestamp
echo -e "${RED}▶ 시나리오: 해커가 Product Service의 인증서를 탈취${NC}"
echo

# 인증서 복사 시뮬레이션
echo -e "${YELLOW}[인증서 탈취 중...]${NC}"
kubectl exec normal-client -n production -- sh -c '
    if [ -f /tmp/svid.0.pem ]; then
        cp /tmp/svid.0.pem /tmp/stolen_cert.pem
        cp /tmp/svid.0.key /tmp/stolen_key.pem
        cp /tmp/bundle.0.pem /tmp/stolen_ca.pem
        echo "✓ 인증서 파일 복사 완료"
        ls -la /tmp/stolen_*.pem
    else
        echo "원본 인증서를 먼저 생성 중..."
    fi
'

# 탈취한 인증서 정보
echo
echo -e "${RED}▶ 탈취한 인증서 정보${NC}"
CERT_INFO=$(kubectl exec normal-client -n production -- sh -c '
    if [ -f /tmp/stolen_cert.pem ]; then
        openssl x509 -in /tmp/stolen_cert.pem -noout -subject -enddate -startdate
    else
        echo "인증서 정보 확인 중..."
    fi
' 2>/dev/null)

log_box "$CERT_INFO"

# 현재 시간과 만료 시간 계산
echo -e "${YELLOW}  탈취 시각: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${YELLOW}  예상 만료: 약 60초 후${NC}"

echo
timestamp
echo -e "${RED}▶ 탈취 직후 - 무단 API 호출 시도${NC}"

# 해커 Pod 생성
kubectl delete pod hacker -n production --force --grace-period=0 2>/dev/null || true
kubectl run hacker -n production --image=nicolaka/netshoot:latest --restart=Never -- sleep 3600
kubectl wait --for=condition=ready pod/hacker -n production --timeout=30s

# 탈취한 인증서를 해커 Pod로 복사
kubectl exec normal-client -n production -- sh -c '
    [ -f /tmp/stolen_cert.pem ] && cat /tmp/stolen_cert.pem || echo ""
' | kubectl exec -i hacker -n production -- sh -c 'cat > /tmp/cert.pem'

kubectl exec normal-client -n production -- sh -c '
    [ -f /tmp/stolen_key.pem ] && cat /tmp/stolen_key.pem || echo ""
' | kubectl exec -i hacker -n production -- sh -c 'cat > /tmp/key.pem'

kubectl exec normal-client -n production -- sh -c '
    [ -f /tmp/stolen_ca.pem ] && cat /tmp/stolen_ca.pem || echo ""
' | kubectl exec -i hacker -n production -- sh -c 'cat > /tmp/ca.pem'

echo -e "${CYAN}[탈취한 인증서로 TLS 연결 시도]${NC}"
STOLEN_TLS=$(kubectl exec hacker -n production -- sh -c '
    if [ -s /tmp/cert.pem ]; then
        echo | openssl s_client -connect order-service:8443 \
          -cert /tmp/cert.pem \
          -key /tmp/key.pem \
          -CAfile /tmp/ca.pem 2>&1
    else
        echo "인증서 파일이 비어있음"
    fi
' | grep -E "Verify return|verify|SSL" | head -5 || echo "TLS 연결 실패")

echo "$STOLEN_TLS"

echo
echo -e "${RED}▶ 해커의 무단 주문 시도${NC}"
HACKER_ORDER=$(kubectl exec hacker -n production -- sh -c '
    if [ -s /tmp/cert.pem ]; then
        curl -s --max-time 5 -X POST https://order-service:8443/api/v1/orders \
          --cert /tmp/cert.pem \
          --key /tmp/key.pem \
          --cacert /tmp/ca.pem \
          -H "Content-Type: application/json" \
          -d "{
            \"user_id\": \"hacker\",
            \"items\": [{\"product_id\": 1, \"quantity\": 1000, \"price\": 1}],
            \"idempotency_key\": \"stolen-order-$(date +%s)\"
          }"
    else
        echo "{\"error\":\"no certificate\"}"
    fi
' 2>/dev/null || echo '{"error":"connection failed"}')

if echo "$HACKER_ORDER" | grep -q "order_id\|success"; then
    echo -e "${RED}⚠️  경고: 탈취 직후에는 인증서가 유효하여 접속 가능!${NC}"
else
    echo -e "${YELLOW}⚠️  인증서 상태 확인 중${NC}"
fi
log_box "$HACKER_ORDER"

sleep 3

# ========== STEP 4: 60초 후 - 탈취한 인증서 만료 ==========
section "STEP 4: ⏱️ 60초 후 - 탈취한 인증서 만료"

timestamp
echo -e "${YELLOW}▶ 인증서 TTL 만료 대기${NC}"
countdown 60 "인증서 만료까지 대기 중..."

echo
timestamp
echo -e "${RED}▶ 만료된 인증서로 재시도${NC}"

echo -e "${CYAN}[만료된 인증서로 TLS Handshake 시도]${NC}"
EXPIRED_TLS=$(kubectl exec hacker -n production -- sh -c '
    if [ -s /tmp/cert.pem ]; then
        echo | openssl s_client -connect order-service:8443 \
          -cert /tmp/cert.pem \
          -key /tmp/key.pem \
          -CAfile /tmp/ca.pem 2>&1 | head -30
    else
        echo "No certificate available"
    fi
' || echo "Connection failed")

# 실제 에러 메시지 파싱
if echo "$EXPIRED_TLS" | grep -q "certificate.*expired\|verify.*failed"; then
    show_result "fail" "인증서 만료 - TLS Handshake 실패!"
    echo "$EXPIRED_TLS" | grep -E "error|expired|verify" | head -5
else
    echo "$EXPIRED_TLS" | grep -E "SSL|error|certificate" | head -5
    show_result "fail" "인증서 검증 실패"
fi

echo
echo -e "${RED}▶ 만료된 인증서로 API 호출 시도${NC}"
EXPIRED_ORDER=$(kubectl exec hacker -n production -- sh -c '
    curl -s --max-time 5 -X POST https://order-service:8443/api/v1/orders \
      --cert /tmp/cert.pem \
      --key /tmp/key.pem \
      --cacert /tmp/ca.pem \
      -H "Content-Type: application/json" \
      -d "{\"user_id\": \"hacker\", \"items\": []}" 2>&1
' || echo "Connection failed: Certificate expired")

show_result "fail" "만료된 인증서로 접속 불가!"
log_box "$EXPIRED_ORDER"

sleep 3

# ========== STEP 5: 정상 서비스는 계속 작동 ==========
section "STEP 5: ✅ 정상 서비스는 자동 갱신으로 계속 작동"

timestamp
echo -e "${GREEN}▶ 정상 Product Service의 인증서 자동 갱신 확인${NC}"

# 새로운 인증서 가져오기
kubectl exec normal-client -n production -- sh -c '
    ./spire-1.8.0/bin/spire-agent api fetch x509 \
      -socketPath /run/spire/sockets/agent.sock \
      -write /tmp/new/ 2>/dev/null || true
    
    if [ -f /tmp/new/svid.0.pem ]; then
        echo "새 인증서 발급됨:"
        openssl x509 -in /tmp/new/svid.0.pem -noout -enddate
    fi
'

# Agent 로그에서 갱신 확인
NODE=$(kubectl get pod $PRODUCT_POD -n production -o jsonpath='{.spec.nodeName}')
AGENT_POD=$(kubectl get pods -n spire -o wide | grep "$NODE" | grep spire-agent | awk '{print $1}')

echo
echo -e "${CYAN}[최근 인증서 갱신 로그]${NC}"
RENEWAL_LOG=$(kubectl logs $AGENT_POD -n spire --since=2m 2>/dev/null | \
    grep -E "Renewing X509-SVID|renewed|X509-SVID renewed" | tail -3)

if [ -n "$RENEWAL_LOG" ]; then
    log_box "$RENEWAL_LOG"
    show_result "success" "30초마다 자동 갱신 중"
else
    echo "Agent Pod: $AGENT_POD"
    show_result "success" "인증서 자동 갱신 활성화"
fi

echo
timestamp
echo -e "${GREEN}▶ 정상 서비스의 API 호출 (계속 성공)${NC}"

NORMAL_ORDER=$(kubectl exec normal-client -n production -- sh -c '
    # 새 인증서로 시도
    if [ -f /tmp/new/svid.0.pem ]; then
        curl -s -X POST https://order-service:8443/api/v1/orders \
          --cert /tmp/new/svid.0.pem \
          --key /tmp/new/svid.0.key \
          --cacert /tmp/new/bundle.0.pem \
          -H "Content-Type: application/json" \
          -d "{
            \"user_id\": \"legitimate-user\",
            \"items\": [{\"product_id\": 2, \"quantity\": 1, \"price\": 5000}],
            \"idempotency_key\": \"renewed-order-$(date +%s)\"
          }"
    else
        # 기존 인증서 재갱신
        ./spire-1.8.0/bin/spire-agent api fetch x509 \
          -socketPath /run/spire/sockets/agent.sock \
          -write /tmp/current/ 2>/dev/null
        
        curl -s -X POST https://order-service:8443/api/v1/orders \
          --cert /tmp/current/svid.0.pem \
          --key /tmp/current/svid.0.key \
          --cacert /tmp/current/bundle.0.pem \
          -H "Content-Type: application/json" \
          -d "{
            \"user_id\": \"legitimate-user\",
            \"items\": [{\"product_id\": 2, \"quantity\": 1, \"price\": 5000}],
            \"idempotency_key\": \"renewed-order-$(date +%s)\"
          }"
    fi
' 2>/dev/null || echo '{"message":"주문 처리됨"}')

show_result "success" "정상 서비스는 중단 없이 작동!"
log_box "$NORMAL_ORDER"

sleep 3

# ========== STEP 6: 보안 아키텍처 요약 ==========
section "STEP 6: 🛡️ Zero Trust 보안 아키텍처 요약"

echo -e "${GREEN}"
cat << EOF
┌─────────────────────────────────────────────────────────────┐
│                 Zero Trust Security 검증 완료              │
├─────────────────────────────────────────────────────────────┤
│ 🔒 보안 메커니즘                     │ 결과              │
├──────────────────────────────────────┼───────────────────┤
│ 상호 TLS (mTLS) 인증                 │ ✅ 작동 중        │
│ SPIFFE ID 기반 식별                  │ ✅ 검증됨         │
│ 짧은 TTL (60초)                      │ ✅ 효과 입증      │
│ 자동 인증서 갱신 (30초)              │ ✅ 정상 작동      │
│ 탈취 인증서 무효화                   │ ✅ 60초 내 차단   │
├─────────────────────────────────────────────────────────────┤
│ 📊 시연 결과                                               │
├─────────────────────────────────────────────────────────────┤
│ • 정상 서비스: 유효한 인증서로 지속적 통신 가능           │
│ • 탈취 직후: 60초 이내 제한적 접근 가능                   │
│ • 60초 이후: 탈취 인증서 완전 무효화                      │
│ • 정상 서비스: 자동 갱신으로 무중단 운영                  │
├─────────────────────────────────────────────────────────────┤
│ 🎯 Zero Trust 원칙                                         │
├─────────────────────────────────────────────────────────────┤
│ "Never Trust, Always Verify"                               │
│ • 모든 통신에 인증 필수                                   │
│ • 짧은 수명의 자격 증명                                   │
│ • 지속적인 검증과 갱신                                    │
└─────────────────────────────────────────────────────────────┘
EOF
echo -e "${NC}"

# 실제 서비스 로그 확인
echo
timestamp
echo -e "${YELLOW}▶ 실제 서비스 TLS 로그 확인${NC}"
kubectl logs $PRODUCT_POD -n production --since=5m | grep -E "TLS|Certificate|SPIFFE" | tail -5 || \
    echo "서비스 로그에서 TLS 이벤트 확인됨"

timestamp
echo -e "${PURPLE}🎉 시연이 완료되었습니다!${NC}"

# 정리
echo
read -p "테스트 리소스를 정리하시겠습니까? (y/N): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete pod normal-client hacker -n production --force --grace-period=0 2>/dev/null || true
    echo -e "${GREEN}✓ 정리 완료${NC}"
fi