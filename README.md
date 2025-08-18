# EKS Production Cluster Architecture

## 📋 클러스터 개요

### 기본 정보
- **클러스터명**: prod
- **Region**: ap-northeast-2 (Seoul)
- **Kubernetes 버전**: v1.33.3-eks
- **VPC ID**: vpc-0b2e9abf762494044
- **생성 시간**: 2025년 8월 18일

### 노드 구성
| 노드 타입 | 개수 | OS | 인스턴스 타입 |
|----------|------|----|--------------| 
| EKS Managed | 4 | Amazon Linux 2023 | t4g.medium (ARM64) |
| Karpenter | 1 | Bottlerocket | 자동 스케일링 |

## 🏗️ 아키텍처 구성도
┌─────────────────────────────────────────────────────────────────────┐
│                          Internet Gateway                           │
└─────────────────────────────────────────────────────────────────────┘
│
┌───────────────┴────────────────┐
│   NGINX Ingress Controller     │
│   (LoadBalancer)               │
└───────────────┬────────────────┘
│
┌───────────────────────────┴────────────────────────────┐
│                                                         │
┌───────┴──────┐                                     ┌───────────┴──────┐
│Product Service│                                     │ Order Service    │
│  (2 Pods)     │                                     │   (2 Pods)       │
└───────┬──────┘                                     └───────────┬──────┘
│                                                         │
└──────────────────┬─────────────────────────────────────┘
│
┌──────┴──────┐
│    Kafka     │
│ (StatefulSet)│
└──────┬──────┘
│
┌──────┴──────┐
│  DynamoDB    │
│  (External)  │
└─────────────┘
## 🚀 배포된 서비스

### Production 네임스페이스

#### 1. Product Service
- **Image**: `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v5`
- **Replicas**: 2
- **Port**: 8081
- **IAM Role**: `arn:aws:iam::928475935003:role/EKSProductServiceRole`
- **DynamoDB Table**: `products-table`

#### 2. Order Service  
- **Image**: `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/order-service:v2`
- **Replicas**: 2
- **Port**: 8080
- **IAM Role**: `arn:aws:iam::928475935003:role/EKSOrderServiceRole`
- **DynamoDB Table**: `orders`

#### 3. Kafka
- **Type**: StatefulSet
- **Replicas**: 1
- **Port**: 9092
- **Service**: `kafka-service.production.svc.cluster.local`

## 📊 모니터링 스택

### Prometheus Stack
- **Grafana**: http://aa0f272db301b40e19218d5f38ace125-16d29c4eba987a3e.elb.ap-northeast-2.amazonaws.com
- **Prometheus**: Internal ClusterIP
- **AlertManager**: Configured
- **Node Exporter**: DaemonSet on all nodes

### Loki Stack
- **Version**: 2.9.13
- **Components**: Distributor, Ingester, Querier, Query-Frontend
- **Promtail**: DaemonSet for log collection

### Kubernetes Dashboard
- **Headlamp**: http://ad610fdaa91464022ae22e719a53a468-0ff550a48fbe1c01.elb.ap-northeast-2.amazonaws.com

## 🌐 네트워킹

### Ingress
- **Controller**: NGINX Ingress Controller
- **LoadBalancer**: k8s-ingressn-ingressn-c6a927d7ff-cb6fb2f096d5debb.elb.ap-northeast-2.amazonaws.com
- **Routes**:
  - `/products/*` → product-service:80
  - `/orders/*` → order-service:80

### Service Endpoints
```bash
# Product API
curl http://k8s-ingressn-ingressn-c6a927d7ff-cb6fb2f096d5debb.elb.ap-northeast-2.amazonaws.com/products/api/v1/health

# Order API  
curl http://k8s-ingressn-ingressn-c6a927d7ff-cb6fb2f096d5debb.elb.ap-northeast-2.amazonaws.com/orders/api/v1/health
🔧 설정 관리
ConfigMap: app-config
yamlAWS_REGION: ap-northeast-2
DYNAMODB_ORDERS_TABLE: orders
DYNAMODB_PRODUCTS_TABLE: products-table
KAFKA_BROKERS: kafka-service.production.svc.cluster.local:9092
KAFKA_ENABLED: "false"  # 환경변수로 true 오버라이드됨
ServiceAccounts (IRSA)

order-service-sa: EKSOrderServiceRole
product-service-sa: EKSProductServiceRole

📦 자동 스케일링
Karpenter

Version: v0.31.0
Provisioner: default
Node Selection: ARM64 우선

HPA

현재 비활성화 (추후 설정 예정)

🗂️ 네임스페이스별 리소스 현황
NamespacePodsServicesDeploymentsStatefulSetsDaemonSetsproduction53210default26281062ingress-nginx53001karpenter21100kube-system1810304
🛠️ 관리 명령어
로그 확인
bash# Product Service 로그
kubectl logs -f deployment/product-service -n production

# Order Service 로그
kubectl logs -f deployment/order-service -n production

# Kafka 로그
kubectl logs -f kafka-0 -n production
배포 업데이트
bash# 이미지 업데이트
kubectl set image deployment/product-service product-service=928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v6 -n production

# 롤아웃 상태 확인
kubectl rollout status deployment/product-service -n production
스케일링
bash# 수동 스케일링
kubectl scale deployment product-service --replicas=3 -n production
📝 CI/CD 파이프라인
ECR 리포지토리

928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service
928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/order-service

빌드 및 푸시
bash# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 빌드 (ARM64)
docker buildx build --platform linux/arm64 -t 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v6 --push .
🔐 보안
IAM Roles (IRSA)

Pod가 AWS 서비스에 접근 시 IAM Role 사용
DynamoDB 접근 권한 포함

Network Policies

현재 미적용 (추후 구성 예정)

📈 모니터링 대시보드
Grafana 대시보드

Kubernetes Cluster Overview
Pod/Container Metrics
NGINX Ingress Controller
Node Exporter Full

주요 메트릭

CPU/Memory 사용률
Request/Response 시간
Error Rate
Kafka Consumer Lag

🚨 트러블슈팅
Pod 재시작
bashkubectl rollout restart deployment/product-service -n production
Kafka 토픽 확인
bashkubectl exec -it kafka-0 -n production -- kafka-topics.sh --list --bootstrap-server localhost:9092
DynamoDB 연결 테스트
bashaws dynamodb list-tables --region ap-northeast-2
📚 추가 문서

Kubernetes 매니페스트
Helm Charts
GitHub 리포지토리


Last Updated: 2025-08-18
Maintained by: Cloud Wave Best Zizon Team
EOF
echo "README.md created successfully!"

### 2. 매니페스트 파일 저장
```bash
# manifests 디렉토리 생성
mkdir -p manifests

# Product Service Deployment
kubectl get deployment product-service -n production -o yaml > manifests/product-service-deployment.yaml

# Order Service Deployment  
kubectl get deployment order-service -n production -o yaml > manifests/order-service-deployment.yaml

# Kafka StatefulSet
kubectl get statefulset kafka -n production -o yaml > manifests/kafka-statefulset.yaml

# Ingress
kubectl get ingress msa-ingress -n production -o yaml > manifests/ingress.yaml

# ConfigMap
kubectl get configmap app-config -n production -o yaml > manifests/app-config.yaml

echo "Manifest files saved to ./manifests/"
3. 빠른 참조 스크립트 생성
bashcat << 'EOF' > quick-reference.sh
#!/bin/bash

# EKS Cluster Quick Reference

export LB_URL="http://k8s-ingressn-ingressn-c6a927d7ff-cb6fb2f096d5debb.elb.ap-northeast-2.amazonaws.com"
export GRAFANA_URL="http://aa0f272db301b40e19218d5f38ace125-16d29c4eba987a3e.elb.ap-northeast-2.amazonaws.com"
export HEADLAMP_URL="http://ad610fdaa91464022ae22e719a53a468-0ff550a48fbe1c01.elb.ap-northeast-2.amazonaws.com"

echo "=== EKS Cluster Status ==="
echo "Cluster: prod"
echo "Region: ap-northeast-2"
echo ""
echo "=== Service URLs ==="
echo "API Gateway: $LB_URL"
echo "Grafana: $GRAFANA_URL"
echo "Headlamp: $HEADLAMP_URL"
echo ""
echo "=== Quick Commands ==="
echo "Product Service Logs: kubectl logs -f deployment/product-service -n production"
echo "Order Service Logs: kubectl logs -f deployment/order-service -n production"
echo "All Pods: kubectl get pods -n production"
EOF

chmod +x quick-reference.sh
