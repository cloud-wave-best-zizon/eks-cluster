#!/bin/bash

# Simple WAF Attack Script - macOS 호환 버전
# 전세계 다양한 국가에서 WAF 차단을 유도

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# API 설정
API_ENDPOINT="https://api.cloudwave10.shop"

echo -e "${BLUE}🌍 Simple WAF Attack Simulation${NC}"
echo -e "${BLUE}===============================${NC}"

# 함수: 최신 Amazon Linux AMI 가져오기
get_latest_ami() {
    local region=$1
    aws ec2 describe-images \
        --region $region \
        --owners amazon \
        --filters 'Name=name,Values=amzn2-ami-hvm-*' 'Name=state,Values=available' \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null
}

# 함수: 공격 스크립트 생성 (Base64 인코딩)
create_attack_userdata() {
    cat << 'ATTACK_SCRIPT' | base64
#!/bin/bash
yum update -y
yum install -y curl

# 5분 후에 공격 시작 (인스턴스 완전 시작 대기)
sleep 300

echo "🚀 Starting WAF attack from $(curl -s ifconfig.me) at $(date)"

# 30초 동안 집중 공격 (Rate Limit: 10/min 초과)
for i in {1..60}; do
    curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/health" &
    curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/products/PROD001" &
    sleep 0.5
done

echo "✅ Attack completed at $(date)"
ATTACK_SCRIPT
}

# 함수: 리전별 인스턴스 생성
create_attack_instance() {
    local region=$1
    local country=$2
    
    echo -e "${CYAN}📍 Creating attack instance in $country ($region)${NC}"
    
    # AMI 가져오기
    AMI_ID=$(get_latest_ami $region)
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
        echo -e "${RED}  ❌ Could not find AMI in $region${NC}"
        return 1
    fi
    
    # 공격 스크립트 생성
    USER_DATA=$(create_attack_userdata)
    
    # 인스턴스 생성
    echo -e "${YELLOW}  Launching EC2 instance...${NC}"
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$region" \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type t3.nano \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WAF-Attack-$region},{Key=Country,Value=$country}]" \
        --query 'Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
        echo -e "${GREEN}  ✅ Instance created: $INSTANCE_ID${NC}"
        
        # 인스턴스 정보 저장
        echo "$region:$INSTANCE_ID:$country" >> /tmp/waf-instances.txt
        return 0
    else
        echo -e "${RED}  ❌ Failed to create instance in $region${NC}"
        return 1
    fi
}

# 함수: 모든 인스턴스 종료
cleanup_instances() {
    echo -e "${YELLOW}🧹 Cleaning up all WAF attack instances...${NC}"
    
    # 저장된 인스턴스들 종료
    if [ -f /tmp/waf-instances.txt ]; then
        while IFS=: read -r region instance_id country; do
            echo -e "${YELLOW}  Terminating $instance_id in $region...${NC}"
            aws ec2 terminate-instances --region "$region" --instance-ids "$instance_id" >/dev/null 2>&1
        done < /tmp/waf-instances.txt
        rm -f /tmp/waf-instances.txt
    fi
    
    # 추가로 태그로 찾아서 정리
    regions="us-east-1 us-west-2 eu-central-1 eu-west-2 ap-northeast-1 ap-south-1 ap-southeast-1 me-south-1 sa-east-1 af-south-1"
    
    for region in $regions; do
        echo -e "${YELLOW}  Checking $region for remaining instances...${NC}"
        INSTANCE_IDS=$(aws ec2 describe-instances \
            --region "$region" \
            --filters "Name=tag:Name,Values=WAF-Attack-*" "Name=instance-state-name,Values=running,pending" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text 2>/dev/null)
        
        if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
            echo -e "${YELLOW}    Found instances: $INSTANCE_IDS${NC}"
            aws ec2 terminate-instances --region "$region" --instance-ids $INSTANCE_IDS >/dev/null 2>&1
        fi
    done
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# 함수: OpenSearch 대시보드 정보 출력
show_dashboard_info() {
    echo -e "${BLUE}📊 OpenSearch Dashboard 모니터링 가이드${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""
    echo -e "${CYAN}1. 대시보드 접속:${NC}"
    echo "   - OpenSearch Domain: opensearch-waf-logs"
    echo "   - Index Pattern: waf-logs-*"
    echo ""
    echo -e "${CYAN}2. 지도 시각화:${NC}"
    echo "   - Visualize > Maps > Create new map"
    echo "   - Add layer > Documents"
    echo "   - Index: waf-logs-*"
    echo "   - Geospatial field: geo_location"
    echo ""
    echo -e "${CYAN}3. 필터 설정:${NC}"
    echo "   - action: BLOCK"
    echo "   - @timestamp: Last 1 hour"
    echo ""
    echo -e "${CYAN}4. 예상 결과:${NC}"
    echo "   🔴 미국, 독일, 일본, 인도, 영국, 싱가포르, 중동, 브라질, 남아프리카, 홍콩에 빨간점"
    echo "   🔴 각 지역당 60+ 차단 이벤트"
    echo ""
    echo -e "${YELLOW}⏰ WAF 로그가 OpenSearch에 표시되기까지 10-15분 소요됩니다.${NC}"
}

# 메인 실행
main() {
    case "${1:-}" in
        "cleanup")
            cleanup_instances
            exit 0
            ;;
        "dashboard")
            show_dashboard_info
            exit 0
            ;;
    esac
    
    echo -e "${GREEN}🚀 Starting Global WAF Attack Simulation...${NC}"
    echo ""
    
    # 임시 파일 초기화
    > /tmp/waf-instances.txt
    
    # 리전과 국가 목록 (간단한 배열 형태)
    regions_and_countries="
    us-east-1:미국_동부
    us-west-2:미국_서부
    eu-central-1:독일
    eu-west-2:영국
    ap-northeast-1:일본
    ap-south-1:인도
    ap-southeast-1:싱가포르
    me-south-1:중동_바레인
    sa-east-1:브라질
    af-south-1:남아프리카
    ap-east-1:홍콩
    "
    
    # 각 리전에 공격 인스턴스 생성
    echo "$regions_and_countries" | while IFS=: read -r region country; do
        # 빈 줄 건너뛰기
        [ -z "$region" ] && continue
        
        # 국가명에서 _ 를 공백으로 변환
        country_display=$(echo "$country" | sed 's/_/ /g')
        
        create_attack_instance "$region" "$country_display"
        
        # 리전간 딜레이
        sleep 3
    done
    
    echo ""
    echo -e "${GREEN}✅ All attack instances have been created!${NC}"
    echo ""
    echo -e "${YELLOW}⏰ Attacks will start in 5 minutes (allowing instances to fully boot)${NC}"
    echo -e "${YELLOW}🎯 Each attack will run for 30 seconds with rapid requests${NC}"
    echo ""
    
    show_dashboard_info
    
    echo ""
    echo -e "${CYAN}💡 Commands:${NC}"
    echo -e "${CYAN}  $0 cleanup     - Terminate all instances${NC}"
    echo -e "${CYAN}  $0 dashboard   - Show dashboard info${NC}"
    echo ""
    
    # 사용자에게 정리 옵션 제공
    read -p "$(echo -e ${YELLOW}Instances are launching. Terminate them after attack? [y/N]:${NC} )" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⏰ Will cleanup instances in 10 minutes...${NC}"
        sleep 600  # 10분 대기
        cleanup_instances
    else
        echo -e "${YELLOW}💡 Instances will keep running. Use '$0 cleanup' to terminate later.${NC}"
    fi
}

# 스크립트 실행
main "$@"