#!/bin/bash

# ==============================================================================
# 설정 (Configuration)
# ==============================================================================

# ALB의 DNS 주소
ALB_URL="https://k8s-producti-msaingre-a832bcc2c1-234292718.ap-northeast-2.elb.amazonaws.com"
# 실제 서비스 도메인 (Host 헤더에 사용)
HOST_HEADER="api.cloudwave10.shop"

# 공격 시나리오 설정 - WAF Rate limit (10/min) 테스트용
ATTACK_WAVES=5           # 공격 웨이브 수
REQUESTS_PER_WAVE=25     # 웨이브당 요청 수 (10/min 제한 초과)
REQUEST_DELAY=0.1        # 요청 간 딜레이 (초) - 너무 빠르면 카운팅 안될 수 있음
WAVE_DELAY=5            # 웨이브 간 딜레이 (초)

# ==============================================================================
# IP 목록
# ==============================================================================
COUNTRY_KEYS=(
    "Korea-Seoul" "Korea-Busan" "Japan-Tokyo" "China-Beijing" "China-Shanghai" "NorthKorea-Pyongyang"
    "Singapore" "Vietnam-Hanoi" "India-Mumbai" "UK-London" "Germany-Frankfurt" "France-Paris"
    "Russia-Moscow" "USA-NewYork" "USA-LosAngeles" "USA-SanFrancisco" "Canada-Toronto" "Mexico-MexicoCity"
)
COUNTRY_IPS=(
    "211.234.10.20" "1.177.60.5" "1.1.1.1" "114.114.114.114" "180.163.0.0" "175.45.176.0"
    "103.4.96.0" "113.160.0.0" "49.205.0.0" "81.139.0.0" "85.88.0.0" "90.85.0.0"
    "77.88.55.55" "74.125.224.72" "173.252.74.22" "38.104.0.0" "24.114.0.0" "189.203.0.0"
)

USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15"
    "curl/7.81.0 (Attack-Test)"
    "python-requests/2.31.0"
    "SQLMap/1.7 (suspicious)"
)

# ==============================================================================
# 향상된 API 호출 함수
# ==============================================================================

# 디버그 정보 포함 요청 함수
send_request_with_debug() {
    local IP="$1"
    local UA="$2"
    local ENDPOINT="$3"
    local METHOD="${4:-GET}"
    
    # 응답을 임시 파일에 저장
    TEMP_FILE="/tmp/waf_response_$$_$(date +%s%N).txt"
    
    # 상세 응답 정보 수집 (-i: 헤더 포함, -w: 추가 정보)
    HTTP_CODE=$(curl -i -s -o "$TEMP_FILE" -w "%{http_code}" \
        -X "$METHOD" \
        "$ALB_URL$ENDPOINT" \
        -H "Host: $HOST_HEADER" \
        -H "X-Forwarded-For: $IP" \
        -H "X-Real-IP: $IP" \
        -H "X-Original-IP: $IP" \
        -H "CF-Connecting-IP: $IP" \
        -H "User-Agent: $UA" \
        -H "X-Attack-Test: true" \
        --insecure \
        --max-time 5 \
        2>/dev/null)
    
    # 403 응답인 경우 WAF 차단 확인
    if [[ "$HTTP_CODE" == "403" ]]; then
        echo -e "\n${RED}🚫 BLOCKED!${NC} Status: $HTTP_CODE from IP: $IP"
        # WAF 응답 헤더 확인
        grep -i "x-amzn-waf\|x-amzn-errortype" "$TEMP_FILE" 2>/dev/null
    fi
    
    rm -f "$TEMP_FILE" 2>/dev/null
    echo "$HTTP_CODE"
}

# 1. Health Check
send_health_check() {
    send_request_with_debug "$1" "$2" "/api/v1/health" "GET"
}

# 2. Product 조회
send_get_product() {
    send_request_with_debug "$1" "$2" "/api/v1/products/PROD001" "GET"
}

# 3. Suspicious Pattern (SQL Injection 시뮬레이션)
send_suspicious_request() {
    # URL 인코딩된 SQL injection 패턴
    send_request_with_debug "$1" "$2" "/api/v1/products/PROD001%27%20OR%20%271%27%3D%271" "GET"
}

# ==============================================================================
# WAF 설정 확인 함수
# ==============================================================================

check_waf_status() {
    echo -e "\n${CYAN}=== WAF Configuration Check ===${NC}"
    
    # WAF 상태 확인 (AWS CLI 필요)
    if command -v aws &> /dev/null; then
        echo "Checking WAF WebACL status..."
        aws wafv2 get-web-acl \
            --name alb-waf \
            --scope REGIONAL \
            --id 848a2061-0ed1-414d-b866-0e49a34a06d3 \
            --region ap-northeast-2 \
            --query 'WebACL.Rules[?Name==`Rate-limit-rule`].{Name:Name,Action:Action.Block,RateLimit:Statement.RateBasedStatement.Limit}' \
            --output table 2>/dev/null || echo "AWS CLI check failed - continuing anyway"
    else
        echo "AWS CLI not found - skipping WAF status check"
    fi
    echo ""
}

# ==============================================================================
# 메인 실행
# ==============================================================================

# 색상 정의
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     Enhanced WAF Rate Limit Test v2.0     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo -e "${CYAN}Target: $HOST_HEADER${NC}"
echo -e "${YELLOW}Config: ${ATTACK_WAVES} waves × ${REQUESTS_PER_WAVE} requests${NC}"
echo -e "${YELLOW}Rate Limit: 10 requests/minute per IP${NC}"
echo -e "${YELLOW}Expected: Requests 11+ should be BLOCKED (403)${NC}\n"

# WAF 상태 확인
check_waf_status

# 통계 초기화
declare -A STATS
SUCCESS=0
FAILED=0  
BLOCKED=0
OTHER=0
START_TIME=$(date +%s)
SCENARIOS=("send_health_check" "send_get_product" "send_suspicious_request")

# 공격 실행
echo -e "${MAGENTA}=== Starting Attack Simulation ===${NC}\n"

for wave in $(seq 1 $ATTACK_WAVES); do
    # 랜덤 IP 선택
    RANDOM_INDEX=$((RANDOM % ${#COUNTRY_KEYS[@]}))
    ATTACK_KEY=${COUNTRY_KEYS[$RANDOM_INDEX]}
    ATTACK_IP=${COUNTRY_IPS[$RANDOM_INDEX]}
    
    echo -e "${YELLOW}Wave ${wave}/${ATTACK_WAVES}:${NC} ${CYAN}${ATTACK_KEY}${NC} (${ATTACK_IP})"
    echo -e "Expected: First 10 requests → 200 OK, Rest → 403 Forbidden\n"
    
    WAVE_200=0; WAVE_403=0
    
    # 연속 요청 (Rate limit 트리거)
    for req in $(seq 1 $REQUESTS_PER_WAVE); do
        # 랜덤 요소 선택
        RANDOM_UA=${USER_AGENTS[$RANDOM % ${#USER_AGENTS[@]}]}
        RANDOM_SCENARIO=${SCENARIOS[$RANDOM % ${#SCENARIOS[@]}]}
        
        # 진행 표시
        printf "  [%02d/%02d] %-25s → " "$req" "$REQUESTS_PER_WAVE" "${RANDOM_SCENARIO:5:20}"
        
        # 요청 전송
        RESPONSE=$($RANDOM_SCENARIO "$ATTACK_IP" "$RANDOM_UA")
        
        # 응답 코드별 카운트
        if [[ "$RESPONSE" == "200" ]]; then
            echo -e "${GREEN}200 OK${NC}"
            ((WAVE_200++))
            ((STATS[200]++))
        elif [[ "$RESPONSE" == "403" ]]; then
            echo -e "${RED}403 BLOCKED! ✓${NC}"
            ((WAVE_403++))
            ((STATS[403]++))
        else
            echo -e "${YELLOW}${RESPONSE}${NC}"
            ((STATS[other]++))
        fi
        
        # Rate limit 회피 방지를 위한 짧은 딜레이
        sleep $REQUEST_DELAY
    done
    
    # 웨이브 결과
    echo -e "\n  Wave Result: ${GREEN}200 OK: ${WAVE_200}${NC}, ${RED}403 Blocked: ${WAVE_403}${NC}"
    
    if [[ $WAVE_403 -gt 0 ]]; then
        echo -e "  ${GREEN}✓ WAF Rate Limiting is WORKING!${NC}"
    else
        echo -e "  ${RED}⚠ WAF might not be blocking properly${NC}"
    fi
    
    # 다음 웨이브 전 대기
    if [[ $wave -lt $ATTACK_WAVES ]]; then
        echo -e "\n  Waiting ${WAVE_DELAY}s before next wave..."
        sleep $WAVE_DELAY
    fi
    echo ""
done

# ==============================================================================
# 최종 결과
# ==============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL=$((STATS[200] + STATS[403] + STATS[other]))

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Test Results Summary            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo -e "${CYAN}Duration: ${DURATION} seconds${NC}"
echo -e "${CYAN}Total Requests: ${TOTAL}${NC}\n"
echo -e "Response Codes:"
echo -e "  ${GREEN}200 OK:${NC}        ${STATS[200]}"
echo -e "  ${RED}403 Forbidden:${NC} ${STATS[403]}"
echo -e "  ${YELLOW}Others:${NC}        ${STATS[other]}"

# WAF 효과성 판단
BLOCK_RATE=$(( STATS[403] * 100 / TOTAL ))
echo -e "\n${CYAN}Block Rate: ${BLOCK_RATE}%${NC}"

if [[ ${STATS[403]} -gt 0 ]]; then
    echo -e "${GREEN}✓ WAF is actively blocking requests!${NC}"
else
    echo -e "${RED}⚠ WARNING: No blocks detected!${NC}"
    echo -e "${YELLOW}Possible issues:${NC}"
    echo "  1. WAF rule might be disabled"
    echo "  2. Rate limit might be set too high"
    echo "  3. X-Forwarded-For header might not be processed"
    echo "  4. WAF might be in COUNT mode instead of BLOCK"
fi

echo -e "\n${BLUE}Next Steps:${NC}"
echo "1. Check AWS WAF console for rule metrics"
echo "2. Review CloudWatch logs for WAF actions"
echo "3. Check OpenSearch dashboard in 5-10 minutes"
echo "4. Verify WAF WebACL is attached to ALB"send_suspicious_request() {
    # URL 인코딩된 SQL injection 패턴
    send_request_with_debug "$1" "$2" "/api/v1/products/PROD001%27%20OR%20%271%27%3D%271" "GET"
}

# 응답 처리 부분 수정
if [[ "$RESPONSE" == "200" ]]; then
    echo -e "${GREEN}200 OK${NC}"
    ((WAVE_200++))
    ((SUCCESS++))
elif [[ "$RESPONSE" == "403" ]]; then
    echo -e "${RED}403 BLOCKED! ✓${NC}"
    ((WAVE_403++))
    ((BLOCKED++))
elif [[ "$RESPONSE" == "000" ]]; then
    echo -e "${YELLOW}TIMEOUT/ERROR${NC}"
    ((OTHER++))
else
    echo -e "${YELLOW}${RESPONSE}${NC}"
    ((OTHER++))
fi