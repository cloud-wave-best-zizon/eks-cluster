#!/bin/bash

# WAF Global Attack Simulation - macOS Compatible
# 전 세계에서 WAF 차단을 유도하여 OpenSearch 대시보드에 표시

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 설정
API_ENDPOINT="https://api.cloudwave10.shop"

echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║         🌍 Global WAF Attack Simulation Tool 🌍            ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 함수: AWS 자격증명 확인
check_aws_credentials() {
    echo -e "${YELLOW}🔍 Checking AWS credentials...${NC}"
    
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${RED}❌ AWS credentials not configured${NC}"
        echo -e "${YELLOW}Please run: aws configure${NC}"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✅ AWS Account: $ACCOUNT_ID${NC}"
    echo ""
}

# 함수: Amazon Linux 2023 AMI 가져오기
get_ami() {
    local region=$1
    
    # SSM Parameter Store에서 최신 AL2023 AMI 가져오기
    local ami_id=$(aws ssm get-parameters \
        --region "$region" \
        --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
        --query 'Parameters[0].Value' \
        --output text 2>/dev/null)
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        # 대체: Amazon Linux 2 AMI
        ami_id=$(aws ssm get-parameters \
            --region "$region" \
            --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
            --query 'Parameters[0].Value' \
            --output text 2>/dev/null)
    fi
    
    echo "$ami_id"
}

# 함수: 보안 그룹 생성
create_security_group() {
    local region=$1
    
    # 기본 VPC 가져오기
    local vpc_id=$(aws ec2 describe-vpcs \
        --region "$region" \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
        return 1
    fi
    
    # 보안 그룹 생성
    local sg_id=$(aws ec2 create-security-group \
        --region "$region" \
        --group-name "waf-attack-sg-$(date +%s)" \
        --description "WAF Attack Test" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text 2>/dev/null)
    
    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
        # 아웃바운드 허용
        aws ec2 authorize-security-group-egress \
            --region "$region" \
            --group-id "$sg_id" \
            --protocol -1 \
            --cidr 0.0.0.0/0 &>/dev/null
        
        echo "$sg_id"
        return 0
    fi
    
    return 1
}

# 함수: 공격 스크립트 (base64 인코딩)
create_userdata() {
    cat << 'SCRIPT' | base64
#!/bin/bash

# 로그 설정
LOG="/var/log/attack.log"
exec 1>>$LOG 2>&1

echo "=== WAF Attack Started at $(date) ==="

# 시스템 정보
IP=$(curl -s http://checkip.amazonaws.com)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Public IP: $IP"
echo "Region: $REGION"

# 패키지 설치
yum update -y
yum install -y curl

# 2분 대기
echo "Waiting 2 minutes..."
sleep 120

# 공격 시작
echo "Starting attack at $(date)"

# 3분간 반복 공격
END=$(($(date +%s) + 180))

while [ $(date +%s) -lt $END ]; do
    echo "Attack wave at $(date)"
    
    # Rate limit 공격 (빠른 요청)
    for i in {1..30}; do
        curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/health" &
        curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/products/PROD001" &
    done
    
    # SQL Injection 시도
    curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/products?id=1' OR '1'='1" &
    
    # XSS 시도
    curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/products?q=<script>alert('xss')</script>" &
    
    wait
    sleep 3
done

echo "Attack completed at $(date)"

# 5분 후 종료
sleep 300
shutdown -h now
SCRIPT
}

# 함수: EC2 인스턴스 생성
launch_instance() {
    local region=$1
    local country=$2
    
    echo -e "${CYAN}🚀 Launching in ${country} (${region})${NC}"
    
    # AMI 가져오기
    local ami=$(get_ami "$region")
    if [ -z "$ami" ] || [ "$ami" = "None" ]; then
        echo -e "${RED}   ❌ No AMI found${NC}"
        return 1
    fi
    
    # 보안 그룹 생성
    local sg=$(create_security_group "$region")
    if [ -z "$sg" ] || [ "$sg" = "None" ]; then
        echo -e "${RED}   ❌ Cannot create security group${NC}"
        return 1
    fi
    
    # UserData
    local userdata=$(create_userdata)
    
    # 인스턴스 생성
    local instance=$(aws ec2 run-instances \
        --region "$region" \
        --image-id "$ami" \
        --instance-type t3.micro \
        --security-group-ids "$sg" \
        --user-data "$userdata" \
        --instance-initiated-shutdown-behavior terminate \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WAF-${country}},{Key=Purpose,Value=WAF-Attack}]" \
        --query 'Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [ -n "$instance" ] && [ "$instance" != "None" ]; then
        echo -e "${GREEN}   ✅ Instance: $instance${NC}"
        echo "$region|$instance|$country|$sg" >> /tmp/waf-instances.txt
        
        # IP 가져오기
        sleep 3
        local ip=$(aws ec2 describe-instances \
            --region "$region" \
            --instance-ids "$instance" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text 2>/dev/null)
        
        if [ -n "$ip" ] && [ "$ip" != "None" ]; then
            echo -e "${GREEN}   ✅ IP: $ip${NC}"
        fi
        
        return 0
    else
        # 보안 그룹 삭제
        aws ec2 delete-security-group --region "$region" --group-id "$sg" &>/dev/null
        echo -e "${RED}   ❌ Failed to create instance${NC}"
        return 1
    fi
}

# 함수: 정리
cleanup_all() {
    echo -e "${YELLOW}🧹 Cleaning up all resources...${NC}"
    
    if [ -f /tmp/waf-instances.txt ]; then
        while IFS='|' read -r region instance country sg; do
            echo -e "${CYAN}Terminating $instance in $region...${NC}"
            
            # 인스턴스 종료
            aws ec2 terminate-instances \
                --region "$region" \
                --instance-ids "$instance" &>/dev/null
            
            # 잠시 대기 후 보안 그룹 삭제
            sleep 2
            aws ec2 delete-security-group \
                --region "$region" \
                --group-id "$sg" &>/dev/null
                
        done < /tmp/waf-instances.txt
        
        rm -f /tmp/waf-instances.txt
    fi
    
    # 추가로 태그 기반 정리
    echo -e "${YELLOW}Checking all regions for remaining instances...${NC}"
    
    # 주요 리전 리스트
    for region in us-east-1 us-west-2 eu-west-1 eu-central-1 ap-northeast-1 ap-southeast-1 ap-south-1 sa-east-1; do
        local instances=$(aws ec2 describe-instances \
            --region "$region" \
            --filters "Name=tag:Purpose,Values=WAF-Attack" "Name=instance-state-name,Values=running,pending" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text 2>/dev/null)
        
        if [ -n "$instances" ] && [ "$instances" != "None" ]; then
            echo -e "${YELLOW}Found instances in $region: $instances${NC}"
            aws ec2 terminate-instances --region "$region" --instance-ids $instances &>/dev/null
        fi
    done
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# 함수: 상태 확인
check_status() {
    echo -e "${BLUE}📊 Instance Status${NC}"
    echo -e "${BLUE}═══════════════${NC}"
    
    if [ -f /tmp/waf-instances.txt ]; then
        while IFS='|' read -r region instance country sg; do
            local state=$(aws ec2 describe-instances \
                --region "$region" \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text 2>/dev/null)
            
            echo -e "${CYAN}$country:${NC} $instance ($state)"
        done < /tmp/waf-instances.txt
    else
        echo "No instances found"
    fi
}

# 메인 실행
main() {
    case "${1:-}" in
        "cleanup")
            cleanup_all
            exit 0
            ;;
        "status")
            check_status
            exit 0
            ;;
        "help")
            echo "Usage:"
            echo "  $0          - Launch attack instances"
            echo "  $0 cleanup  - Terminate all instances"  
            echo "  $0 status   - Check status"
            exit 0
            ;;
    esac
    
    # AWS 체크
    check_aws_credentials
    
    echo -e "${GREEN}🌍 Launching Global WAF Attack${NC}"
    echo -e "${GREEN}═══════════════════════════════${NC}"
    echo ""
    
    # 임시 파일 초기화
    > /tmp/waf-instances.txt
    
    # 리전과 국가 리스트 (간단한 배열)
    regions=(
        "us-east-1:USA-Virginia"
        "us-west-2:USA-Oregon"
        "ca-central-1:Canada"
        "eu-central-1:Germany"
        "eu-west-1:Ireland"
        "eu-west-2:UK-London"
        "eu-west-3:France"
        "eu-north-1:Sweden"
        "ap-northeast-1:Japan"
        "ap-northeast-2:Korea"
        "ap-southeast-1:Singapore"
        "ap-southeast-2:Australia"
        "ap-south-1:India"
        "sa-east-1:Brazil"
    )
    
    # 옵션 리전들
    optional_regions=(
        "ap-east-1:HongKong"
        "me-south-1:UAE"
        "af-south-1:SouthAfrica"
        "eu-south-1:Italy"
    )
    
    success=0
    failed=0
    
    # 메인 리전들 처리
    for entry in "${regions[@]}"; do
        IFS=':' read -r region country <<< "$entry"
        
        if launch_instance "$region" "$country"; then
            ((success++))
        else
            ((failed++))
        fi
        
        # API 제한 방지
        sleep 2
    done
    
    # 옵션 리전 시도
    echo ""
    echo -e "${YELLOW}Trying optional regions...${NC}"
    
    for entry in "${optional_regions[@]}"; do
        IFS=':' read -r region country <<< "$entry"
        
        if launch_instance "$region" "$country"; then
            ((success++))
        else
            echo -e "${YELLOW}   ℹ️  $region may need activation${NC}"
        fi
        
        sleep 2
    done
    
    # 결과 요약
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║         Deployment Summary             ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✅ Launched: $success instances${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Failed: $failed regions${NC}"
    fi
    echo ""
    echo -e "${CYAN}Timeline:${NC}"
    echo "  • Now: Instances starting"
    echo "  • +2min: Attacks begin"
    echo "  • +5min: WAF blocks appear"
    echo "  • +10min: OpenSearch shows data"
    echo "  • +10min: Auto-termination"
    echo ""
    echo -e "${BLUE}OpenSearch Dashboard:${NC}"
    echo "  1. Visualize → Maps"
    echo "  2. Index: waf-logs-*"
    echo "  3. Field: geo_location"
    echo "  4. Filter: action=BLOCK"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo "  $0 status   - Check instances"
    echo "  $0 cleanup  - Terminate all"
    echo ""
    
    # 자동 정리
    read -p "$(echo -e ${YELLOW}'Auto-cleanup in 15min? [y/N]: '${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        (
            sleep 900
            cleanup_all
        ) &
        echo -e "${GREEN}✅ Cleanup scheduled (PID: $!)${NC}"
    else
        echo -e "${YELLOW}Run '$0 cleanup' when done${NC}"
    fi
}

# 실행
main "$@"