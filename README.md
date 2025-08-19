# EKS Production Cluster Architecture

## 🚀 Overview
Production MSA (Microservice Architecture) environment running on Amazon EKS in ap-northeast-2 region.

### 📊 Cluster Statistics
- **Worker Nodes**: 6 (4 ARM64 + 2 Karpenter managed)
- **Microservices**: 2 (Product Service, Order Service)
- **Namespaces**: 10
- **Load Balancers**: 4 (1 ALB, 3 NLB)

## 🏗️ Architecture Diagram

```mermaid
graph TB
    %% Styling
    classDef internet fill:#667eea,stroke:#fff,stroke-width:2px,color:#fff
    classDef alb fill:#f093fb,stroke:#fff,stroke-width:2px,color:#fff
    classDef public fill:#4caf50,stroke:#fff,stroke-width:2px,color:#fff
    classDef private fill:#ff9800,stroke:#fff,stroke-width:2px,color:#fff
    classDef service fill:#3498db,stroke:#fff,stroke-width:2px,color:#fff
    classDef pod fill:#9b59b6,stroke:#fff,stroke-width:2px,color:#fff
    classDef monitoring fill:#00bcd4,stroke:#fff,stroke-width:2px,color:#fff

    %% Internet Layer
    Internet[🌐 Internet]:::internet
    
    %% ALB Layer
    Internet --> ALB[Application Load Balancer<br/>k8s-producti-msaingre-*.elb.amazonaws.com]:::alb
    
    %% Ingress
    ALB --> Ingress[Ingress: msa-ingress<br/>Path-based Routing]
    
    %% VPC
    subgraph VPC[VPC: oliveyoung-prod - 10.1.0.0/16]
        %% Public Subnets
        subgraph PublicSubnets[Public Subnets]
            PubA[Public Subnet 2a<br/>10.1.1.0/24<br/>subnet-00a1df66e269743b3]:::public
            PubC[Public Subnet 2c<br/>10.1.2.0/24<br/>subnet-057b1399a4c256f74]:::public
            
            NAT[NAT Gateway<br/>nat-01bd5bbff1d68472f]
            PubA --> NAT
        end
        
        %% Private Subnets
        subgraph PrivateSubnets[Private Subnets - Worker Nodes]
            subgraph PriA[Private Subnet 2a - 10.1.11.0/24]
                NodeA1[ip-10-1-11-154<br/>Amazon Linux ARM64]:::private
                NodeA2[ip-10-1-11-184<br/>Amazon Linux ARM64]:::private
            end
            
            subgraph PriC[Private Subnet 2c - 10.1.12.0/24]
                NodeC1[ip-10-1-12-64<br/>Amazon Linux ARM64]:::private
                NodeC2[ip-10-1-12-169<br/>Amazon Linux ARM64]:::private
                NodeC3[i-0ca8f63396c2f5a20<br/>Bottlerocket Karpenter]:::private
                NodeC4[i-0e8fcb63c2579bbad<br/>Bottlerocket Karpenter]:::private
            end
        end
        
        %% Services
        subgraph Services[Kubernetes Services]
            SvcProduct[product-service<br/>ClusterIP: 172.20.44.190<br/>Port: 80→8081]:::service
            SvcOrder[order-service<br/>ClusterIP: 172.20.46.38<br/>Port: 80→8080]:::service
            SvcKafka[kafka-service<br/>Headless Service<br/>Port: 9092]:::service
        end
        
        %% Pods
        subgraph Pods[Application Pods]
            PodProduct1[product-service-8ngzd<br/>10.1.12.161:8081]:::pod
            PodProduct2[product-service-msh5x<br/>10.1.11.104:8081]:::pod
            PodOrder1[order-service-n6nvt<br/>10.1.12.58:8080]:::pod
            PodOrder2[order-service-vfjr9<br/>10.1.11.138:8080]:::pod
            PodKafka[kafka-0<br/>10.1.12.88:9092]:::pod
        end
    end
    
    %% Connections
    Ingress -->|/api/v1/products| SvcProduct
    Ingress -->|/api/v1/orders| SvcOrder
    
    SvcProduct --> PodProduct1
    SvcProduct --> PodProduct2
    SvcOrder --> PodOrder1
    SvcOrder --> PodOrder2
    SvcKafka --> PodKafka
    
    PodProduct1 -.->|Events| PodKafka
    PodProduct2 -.->|Events| PodKafka
    PodOrder1 -.->|Events| PodKafka
    PodOrder2 -.->|Events| PodKafka
    
    %% External Services
    subgraph External[External Services]
        DynamoDB[(DynamoDB)]
        ECR[ECR Registry]
    end
    
    PodProduct1 -.->|IAM Role| DynamoDB
    PodProduct2 -.->|IAM Role| DynamoDB
    PodOrder1 -.->|IAM Role| DynamoDB
    PodOrder2 -.->|IAM Role| DynamoDB
```

## 📋 Request Flow Sequence

```mermaid
sequenceDiagram
    participant User
    participant ALB
    participant Ingress
    participant Service
    participant Pod
    participant DynamoDB
    participant Kafka
    
    User->>ALB: HTTP Request<br/>/api/v1/products
    ALB->>Ingress: Route based on path
    Ingress->>Service: Forward to product-service:80
    Service->>Pod: Load balance to Pod:8081
    Pod->>DynamoDB: Query/Write data<br/>(via IAM role)
    Pod->>Kafka: Publish event
    Pod-->>Service: Response
    Service-->>Ingress: Response
    Ingress-->>ALB: Response
    ALB-->>User: HTTP Response
```

## 🔧 Core Components

### Infrastructure
| Component | Details |
|-----------|---------|
| **Cluster Name** | prod |
| **Kubernetes Version** | v1.33 |
| **Region** | ap-northeast-2 |
| **VPC** | oliveyoung-prod (10.1.0.0/16) |
| **Availability Zones** | ap-northeast-2a, ap-northeast-2c |

### Networking
| Component | Details |
|-----------|---------|
| **Ingress Controller** | AWS Load Balancer Controller |
| **Load Balancer Type** | Application Load Balancer (ALB) |
| **Service Type** | ClusterIP (internal) |
| **Pod Networking** | AWS VPC CNI |

### Nodes
| Node | Type | Subnet | IP Address |
|------|------|--------|------------|
| ip-10-1-11-154 | Amazon Linux ARM64 | Private 2a | 10.1.11.154 |
| ip-10-1-11-184 | Amazon Linux ARM64 | Private 2a | 10.1.11.184 |
| ip-10-1-12-64 | Amazon Linux ARM64 | Private 2c | 10.1.12.64 |
| ip-10-1-12-169 | Amazon Linux ARM64 | Private 2c | 10.1.12.169 |
| i-0ca8f63396c2f5a20 | Bottlerocket (Karpenter) | Private 2c | 10.1.12.67 |
| i-0e8fcb63c2579bbad | Bottlerocket (Karpenter) | Private 2c | 10.1.12.192 |

## 🎯 Microservices

### Product Service
- **Deployment**: 2 replicas
- **Image**: 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/product-service:v5
- **Port**: 8081 (container) → 80 (service)
- **Resources**: 
  - Requests: 100m CPU, 128Mi Memory
  - Limits: 200m CPU, 256Mi Memory
- **Service Account**: product-service-sa

### Order Service
- **Deployment**: 2 replicas
- **Image**: 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com/order-service:latest
- **Port**: 8080 (container) → 80 (service)
- **Resources**: 
  - Requests: 100m CPU, 128Mi Memory
  - Limits: 200m CPU, 256Mi Memory
- **Service Account**: order-service-sa

### Kafka
- **Type**: StatefulSet
- **Replicas**: 1
- **Port**: 9092
- **Service Type**: Headless

## 📊 Monitoring Stack

```mermaid
graph LR
    subgraph Monitoring
        Prometheus[📊 Prometheus<br/>Metrics Collection]
        Grafana[📈 Grafana<br/>Visualization]
        Loki[📝 Loki<br/>Log Aggregation]
        Tempo[🔍 Tempo<br/>Distributed Tracing]
        Promtail[🎯 Promtail<br/>Log Shipper]
        Headlamp[👁️ Headlamp<br/>K8s Dashboard]
    end
    
    Prometheus --> Grafana
    Promtail --> Loki
    Loki --> Grafana
    Tempo --> Grafana
```

## 🚀 System Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **AWS Load Balancer Controller** | Manages ALB/NLB | kube-system |
| **Karpenter** | Node autoscaling | karpenter |
| **ArgoCD** | GitOps deployment | argocd |
| **CoreDNS** | Service discovery | kube-system |
| **EBS CSI Driver** | Storage management | kube-system |
| **Metrics Server** | Resource metrics | kube-system |

## 📝 Ingress Rules

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: msa-ingress
  namespace: production
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /api/v1/products
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 80
      - path: /api/v1/orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 80
```

## 🔒 Security Configuration

### Network Security
- ✅ Worker nodes in private subnets
- ✅ NAT Gateway for outbound traffic
- ✅ Security groups for network isolation
- ✅ Network policies for pod-to-pod communication

### IAM & RBAC
- ✅ IRSA (IAM Roles for Service Accounts)
- ✅ Separate service accounts per microservice
- ✅ Least privilege IAM policies
- ✅ RBAC for namespace isolation

### Data Protection
- ✅ EBS encryption at rest
- ✅ TLS for service-to-service communication
- ✅ Secrets management via K8s Secrets

## 📦 Storage

| Storage Class | Provisioner | Type | Binding Mode |
|--------------|-------------|------|--------------|
| gp2 | kubernetes.io/aws-ebs | gp2 | WaitForFirstConsumer |
| gp3 | ebs.csi.aws.com | gp3 | WaitForFirstConsumer |

## 🔄 CI/CD Pipeline

```mermaid
graph LR
    Git[Git Repository] --> ArgoCD[ArgoCD]
    ArgoCD --> Sync{Sync Status}
    Sync -->|OutOfSync| Deploy[Deploy Changes]
    Sync -->|Synced| Monitor[Monitor]
    Deploy --> Validate[Validate Deployment]
    Validate --> Monitor
```

## 📌 Access Points

### External Access
- **ALB Endpoint**: http://k8s-producti-msaingre-a832bcc2c1-1931180001.ap-northeast-2.elb.amazonaws.com
- **Grafana**: http://aa0f272db301b40e19218d5f38ace125-16d29c4eba987a3e.elb.ap-northeast-2.amazonaws.com
- **Headlamp**: http://ad610fdaa91464022ae22e719a53a468-0ff550a48fbe1c01.elb.ap-northeast-2.amazonaws.com

### API Endpoints
- **Product Service**: `/api/v1/products`
- **Order Service**: `/api/v1/orders`
- **Health Check**: `/api/v1/health`

## 🛠️ Deployment Commands

```bash
# Deploy with kubectl
kubectl apply -f eks-cluster-config.yaml

# Check deployment status
kubectl get all -n production

# View logs
kubectl logs -f deployment/product-service -n production

# Scale deployment
kubectl scale deployment product-service --replicas=3 -n production

# Port forward for debugging
kubectl port-forward service/product-service 8080:80 -n production
```

## 📈 Performance Metrics

- **Target CPU Utilization**: 70%
- **Request Timeout**: 30s
- **Health Check Interval**: 15s
- **Pod Disruption Budget**: 1 (minimum available)

## 🔍 Troubleshooting

### Common Issues

1. **Pod not starting**
   ```bash
   kubectl describe pod <pod-name> -n production
   kubectl logs <pod-name> -n production
   ```

2. **Service not reachable**
   ```bash
   kubectl get endpoints -n production
   kubectl get ingress -n production
   ```

3. **Node issues**
   ```bash
   kubectl get nodes
   kubectl describe node <node-name>
   ```

## 📚 Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Karpenter Documentation](https://karpenter.sh/)

---
*Generated: 2025-08-19 | Cluster: prod | Region: ap-northeast-2*
