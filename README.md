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

```
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
```

## 🚀 배포된 서비스

### Production 네임스페이스

#### 1. Product Service
- **Image**: `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v5`
- **Replicas**: 2
- **Port**: 8081
- **IAM Role**: `arn:aws:iam::928475935003:role/EKSProductServiceRole`
- **DynamoDB Table**: `products-table`
- **API Endpoints**:
  - GET `/products/api/v1/health` - 헬스체크
  - POST `/products/api/v1/products` - 상품 생성
  - GET `/products/api/v1/products/{id}` - 상품 조회
  - POST `/products/api/v1/products/{id}/deduct` - 재고 차감

#### 2. Order Service  
- **Image**: `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/order-service:v2`
- **Replicas**: 2
- **Port**: 8080
- **IAM Role**: `arn:aws:iam::928475935003:role/EKSOrderServiceRole`
- **DynamoDB Table**: `orders`
- **API Endpoints**:
  - GET `/orders/api/v1/health` - 헬스체크
  - POST `/orders/api/v1/orders` - 주문 생성
  - GET `/orders/api/v1/orders/{id}` - 주문 조회

#### 3. Kafka
- **Type**: StatefulSet
- **Replicas**: 1
- **Port**: 9092
- **Service**: `kafka-service.production.svc.cluster.local`
- **Topics**: `order-events`

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
# Export LoadBalancer URL
export LB_URL="http://k8s-ingressn-ingressn-c6a927d7ff-cb6fb2f096d5debb.elb.ap-northeast-2.amazonaws.com"

# Product API 테스트
curl $LB_URL/products/api/v1/health

# Order API 테스트
curl $LB_URL/orders/api/v1/health

# 상품 생성
curl -X POST $LB_URL/products/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": "TEST001",
    "name": "Test Product",
    "stock": 100,
    "price": 10000
  }'

# 주문 생성
curl -X POST $LB_URL/orders/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test_user",
    "items": [{
      "product_id": "TEST001",
      "product_name": "Test Product",
      "quantity": 5,
      "price": 10000
    }],
    "idempotency_key": "test-123"
  }'
```

## 🔧 설정 관리

### ConfigMap: app-config
```yaml
AWS_REGION: ap-northeast-2
DYNAMODB_ORDERS_TABLE: orders
DYNAMODB_PRODUCTS_TABLE: products-table
KAFKA_BROKERS: kafka-service.production.svc.cluster.local:9092
KAFKA_ENABLED: "false"  # 환경변수로 true 오버라이드됨
```

### ServiceAccounts (IRSA)
- `order-service-sa`: EKSOrderServiceRole
- `product-service-sa`: EKSProductServiceRole

### 환경변수 오버라이드
```yaml
# Product Service
KAFKA_BROKERS: kafka-service.production.svc.cluster.local:9092
KAFKA_ENABLED: true

# Order Service
KAFKA_BROKERS: kafka-service.production.svc.cluster.local:9092
```

## 📦 자동 스케일링

### Karpenter
- **Version**: v0.31.0
- **Provisioner**: default
- **Node Selection**: ARM64 우선
- **Spot Instance**: 활성화

### HPA (Horizontal Pod Autoscaler)
- 현재 비활성화
- 추후 설정 예정 (CPU 70% 기준)

## 🗂️ 네임스페이스별 리소스 현황

| Namespace | Pods | Services | Deployments | StatefulSets | DaemonSets |
|-----------|------|----------|-------------|--------------|------------|
| production | 5 | 3 | 2 | 1 | 0 |
| default | 26 | 28 | 10 | 6 | 2 |
| ingress-nginx | 5 | 3 | 0 | 0 | 1 |
| karpenter | 2 | 1 | 1 | 0 | 0 |
| kube-system | 18 | 10 | 3 | 0 | 4 |

## 🛠️ 관리 명령어

### 로그 확인
```bash
# Product Service 로그
kubectl logs -f deployment/product-service -n production

# Order Service 로그
kubectl logs -f deployment/order-service -n production

# Kafka 로그
kubectl logs -f kafka-0 -n production

# 특정 Pod 로그
kubectl logs -f <pod-name> -n production

# 이전 Pod 로그 (재시작된 경우)
kubectl logs <pod-name> -n production --previous
```

### 배포 업데이트
```bash
# 이미지 업데이트
kubectl set image deployment/product-service \
  product-service=928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v6 \
  -n production

# 롤아웃 상태 확인
kubectl rollout status deployment/product-service -n production

# 롤아웃 히스토리
kubectl rollout history deployment/product-service -n production

# 롤백
kubectl rollout undo deployment/product-service -n production
```

### 스케일링
```bash
# 수동 스케일링
kubectl scale deployment product-service --replicas=3 -n production

# 현재 replica 확인
kubectl get deployment -n production
```

### Pod 관리
```bash
# Pod 재시작
kubectl rollout restart deployment/product-service -n production

# Pod 삭제 (자동 재생성)
kubectl delete pod <pod-name> -n production

# Pod 상세 정보
kubectl describe pod <pod-name> -n production

# Pod 접속
kubectl exec -it <pod-name> -n production -- /bin/sh
```

## 📝 CI/CD 파이프라인

### ECR 리포지토리
- `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service`
- `928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/order-service`

### 빌드 및 배포 프로세스
```bash
# 1. ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  928475935003.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. 이미지 빌드 (ARM64)
docker buildx build --platform linux/arm64 \
  -t 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v6 \
  --push .

# 3. Kubernetes 배포
kubectl set image deployment/product-service \
  product-service=928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v6 \
  -n production

# 4. 배포 확인
kubectl rollout status deployment/product-service -n production
```

## 🔐 보안

### IAM Roles (IRSA)
- Pod가 AWS 서비스에 접근 시 IAM Role 사용
- DynamoDB 접근 권한 포함
- 최소 권한 원칙 적용

### Network Policies
- 현재 미적용
- 추후 구성 예정

### Secrets Management
- 현재 ConfigMap 사용
- AWS Secrets Manager 연동 예정

## 📈 모니터링 대시보드

### Grafana 대시보드
1. **Kubernetes Cluster Overview**
   - 노드 상태
   - 리소스 사용률
   - Pod 상태

2. **Application Metrics**
   - Request/Response 시간
   - Error Rate
   - Throughput

3. **NGINX Ingress Controller**
   - Request Rate
   - Response Time
   - Error Rate by Service

4. **Node Exporter Full**
   - CPU/Memory/Disk 사용률
   - Network I/O

### 주요 메트릭
- **SLI (Service Level Indicators)**
  - Availability > 99.9%
  - Response Time < 200ms (P95)
  - Error Rate < 1%

- **리소스 사용률**
  - CPU: 평균 20%, 최대 60%
  - Memory: 평균 30%, 최대 70%

## 🚨 트러블슈팅

### 일반적인 문제 해결

#### Pod가 시작되지 않을 때
```bash
# Pod 상태 확인
kubectl get pods -n production

# Pod 이벤트 확인
kubectl describe pod <pod-name> -n production

# Pod 로그 확인
kubectl logs <pod-name> -n production
```

#### Kafka 연결 실패
```bash
# Kafka 상태 확인
kubectl get pod kafka-0 -n production

# Kafka 토픽 확인
kubectl exec -it kafka-0 -n production -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

# Consumer Group 확인
kubectl exec -it kafka-0 -n production -- \
  kafka-consumer-groups.sh --list --bootstrap-server localhost:9092
```

#### DynamoDB 연결 테스트
```bash
# DynamoDB 테이블 목록
aws dynamodb list-tables --region ap-northeast-2

# 테이블 항목 확인
aws dynamodb scan --table-name products-table \
  --region ap-northeast-2 --max-items 5
```

#### 이미지 Pull 실패
```bash
# ECR 로그인 재시도
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  928475935003.dkr.ecr.ap-northeast-2.amazonaws.com

# ImagePullBackOff 해결
kubectl delete pod <pod-name> -n production
```

## 📚 추가 리소스

### GitHub 리포지토리
- [Product Service](https://github.com/cloud-wave-best-zizon/product-service)
- [Order Service](https://github.com/cloud-wave-best-zizon/order-service)

### AWS 리소스
- **DynamoDB Tables**:
  - `products-table`
  - `orders`
- **ECR Repositories**:
  - `product-service`
  - `order-service`

### 유용한 도구
- [K9s](https://k9scli.io/) - Kubernetes CLI UI
- [Lens](https://k8slens.dev/) - Kubernetes IDE
- [kubectl-tree](https://github.com/ahmetb/kubectl-tree) - Resource hierarchy viewer

## 🔄 백업 및 복구

### DynamoDB 백업
```bash
# On-demand 백업
aws dynamodb create-backup \
  --table-name products-table \
  --backup-name products-backup-$(date +%Y%m%d) \
  --region ap-northeast-2

# 백업 목록 확인
aws dynamodb list-backups \
  --table-name products-table \
  --region ap-northeast-2
```

### Kubernetes 리소스 백업
```bash
# 네임스페이스 전체 백업
kubectl get all -n production -o yaml > production-backup.yaml

# ConfigMap 백업
kubectl get configmap -n production -o yaml > configmaps-backup.yaml
```

---
*Last Updated: 2025-08-18*  
*Maintained by: Cloud Wave Best Zizon Team*  
*Version: 1.0.0*
