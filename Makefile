# EKS MSA Makefile
# Usage: make [target]

# Variables
REGION := ap-northeast-2
CLUSTER_NAME := prod
NAMESPACE := production
ECR_REGISTRY := 928475935003.dkr.ecr.ap-northeast-2.amazonaws.com
PRODUCT_IMAGE := $(ECR_REGISTRY)/product-service
ORDER_IMAGE := $(ECR_REGISTRY)/order-service
PRODUCT_VERSION := v5
ORDER_VERSION := v2

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

.PHONY: help
help: ## Show this help message
	@echo "EKS MSA Deployment Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: deploy-all
deploy-all: create-namespace deploy-configmap deploy-kafka deploy-services deploy-ingress ## Deploy all components

.PHONY: create-namespace
create-namespace: ## Create production namespace
	@echo "$(YELLOW)Creating namespace...$(NC)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "$(GREEN)✓ Namespace created$(NC)"

.PHONY: deploy-configmap
deploy-configmap: ## Deploy ConfigMap
	@echo "$(YELLOW)Deploying ConfigMap...$(NC)"
	@kubectl apply -f app-config.yaml
	@echo "$(GREEN)✓ ConfigMap deployed$(NC)"

.PHONY: deploy-kafka
deploy-kafka: ## Deploy Kafka
	@echo "$(YELLOW)Deploying Kafka...$(NC)"
	@kubectl apply -f kafka-statefulset.yaml
	@kubectl wait --for=condition=ready pod/kafka-0 -n $(NAMESPACE) --timeout=120s
	@echo "$(GREEN)✓ Kafka deployed$(NC)"

.PHONY: deploy-services
deploy-services: deploy-product deploy-order ## Deploy all services

.PHONY: deploy-product
deploy-product: ## Deploy Product Service
	@echo "$(YELLOW)Deploying Product Service...$(NC)"
	@kubectl apply -f product-service-deployment.yaml
	@kubectl rollout status deployment/product-service -n $(NAMESPACE) --timeout=120s
	@echo "$(GREEN)✓ Product Service deployed$(NC)"

.PHONY: deploy-order
deploy-order: ## Deploy Order Service
	@echo "$(YELLOW)Deploying Order Service...$(NC)"
	@kubectl apply -f order-service-deployment.yaml
	@kubectl rollout status deployment/order-service -n $(NAMESPACE) --timeout=120s
	@echo "$(GREEN)✓ Order Service deployed$(NC)"

.PHONY: deploy-ingress
deploy-ingress: ## Deploy Ingress
	@echo "$(YELLOW)Deploying Ingress...$(NC)"
	@kubectl apply -f ingress.yaml
	@echo "$(GREEN)✓ Ingress deployed$(NC)"

.PHONY: status
status: ## Check deployment status
	@echo "=== Pods ==="
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "=== Services ==="
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "=== Ingress ==="
	@kubectl get ingress -n $(NAMESPACE)

.PHONY: logs-product
logs-product: ## Show Product Service logs
	@kubectl logs -f deployment/product-service -n $(NAMESPACE)

.PHONY: logs-order
logs-order: ## Show Order Service logs
	@kubectl logs -f deployment/order-service -n $(NAMESPACE)

.PHONY: logs-kafka
logs-kafka: ## Show Kafka logs
	@kubectl logs -f kafka-0 -n $(NAMESPACE)

.PHONY: test
test: ## Test the deployment
	@./test-deployment.sh

.PHONY: scale-product
scale-product: ## Scale Product Service (REPLICAS=3)
	@kubectl scale deployment product-service --replicas=$(REPLICAS) -n $(NAMESPACE)

.PHONY: scale-order
scale-order: ## Scale Order Service (REPLICAS=3)
	@kubectl scale deployment order-service --replicas=$(REPLICAS) -n $(NAMESPACE)

.PHONY: restart-product
restart-product: ## Restart Product Service
	@kubectl rollout restart deployment/product-service -n $(NAMESPACE)

.PHONY: restart-order
restart-order: ## Restart Order Service
	@kubectl rollout restart deployment/order-service -n $(NAMESPACE)

.PHONY: update-product-image
update-product-image: ## Update Product Service image (VERSION=v6)
	@kubectl set image deployment/product-service product-service=$(PRODUCT_IMAGE):$(VERSION) -n $(NAMESPACE)
	@kubectl rollout status deployment/product-service -n $(NAMESPACE)

.PHONY: update-order-image
update-order-image: ## Update Order Service image (VERSION=v3)
	@kubectl set image deployment/order-service order-service=$(ORDER_IMAGE):$(VERSION) -n $(NAMESPACE)
	@kubectl rollout status deployment/order-service -n $(NAMESPACE)

.PHONY: rollback-product
rollback-product: ## Rollback Product Service
	@kubectl rollout undo deployment/product-service -n $(NAMESPACE)

.PHONY: rollback-order
rollback-order: ## Rollback Order Service
	@kubectl rollout undo deployment/order-service -n $(NAMESPACE)

.PHONY: kafka-topics
kafka-topics: ## List Kafka topics
	@kubectl exec -it kafka-0 -n $(NAMESPACE) -- kafka-topics.sh --list --bootstrap-server localhost:9092

.PHONY: kafka-consumer
kafka-consumer: ## Start Kafka consumer (TOPIC=order-events)
	@kubectl exec -it kafka-0 -n $(NAMESPACE) -- kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $(TOPIC) --from-beginning

.PHONY: port-forward-product
port-forward-product: ## Port forward Product Service (8081:8081)
	@kubectl port-forward deployment/product-service 8081:8081 -n $(NAMESPACE)

.PHONY: port-forward-order
port-forward-order: ## Port forward Order Service (8080:8080)
	@kubectl port-forward deployment/order-service 8080:8080 -n $(NAMESPACE)

.PHONY: port-forward-kafka
port-forward-kafka: ## Port forward Kafka (9092:9092)
	@kubectl port-forward kafka-0 9092:9092 -n $(NAMESPACE)

.PHONY: ecr-login
ecr-login: ## Login to ECR
	@aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

.PHONY: build-product
build-product: ecr-login ## Build and push Product Service image
	@cd product-service && \
	docker buildx build --platform linux/arm64 -t $(PRODUCT_IMAGE):$(VERSION) --push .

.PHONY: build-order
build-order: ecr-login ## Build and push Order Service image
	@cd order-service && \
	docker buildx build --platform linux/arm64 -t $(ORDER_IMAGE):$(VERSION) --push .

.PHONY: cleanup
cleanup: ## Delete all resources (WARNING: Destructive!)
	@echo "$(RED)WARNING: This will delete all resources!$(NC)"
	@read -p "Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		kubectl delete namespace $(NAMESPACE) --ignore-not-found=true; \
		echo "$(GREEN)✓ Resources deleted$(NC)"; \
	else \
		echo "$(YELLOW)Cleanup cancelled$(NC)"; \
	fi

.PHONY: backup
backup: ## Backup all YAML manifests
	@mkdir -p backups/$(shell date +%Y%m%d)
	@kubectl get all -n $(NAMESPACE) -o yaml > backups/$(shell date +%Y%m%d)/all-resources.yaml
	@kubectl get configmap -n $(NAMESPACE) -o yaml > backups/$(shell date +%Y%m%d)/configmaps.yaml
	@kubectl get ingress -n $(NAMESPACE) -o yaml > backups/$(shell date +%Y%m%d)/ingress.yaml
	@echo "$(GREEN)✓ Backup completed in backups/$(shell date +%Y%m%d)/$(NC)"
