#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧹 추가 정리 시작...${NC}"

# 1. 중복/깨진 메인 클러스터 파일 삭제
echo -e "${RED}삭제: 깨진 cluster/eks-cluster.yaml${NC}"
rm -f cluster/eks-cluster.yaml
git rm -f cluster/eks-cluster.yaml 2>/dev/null

# 2. 로컬 개발용 파일 삭제
echo -e "${RED}삭제: docker-compose.yaml (로컬 개발용)${NC}"
rm -f docker-compose.yaml
git rm -f docker-compose.yaml 2>/dev/null

# 3. 테스트 스크립트 삭제
echo -e "${RED}삭제: spire-security-demo.sh${NC}"
rm -f spire-security-demo.sh
git rm -f spire-security-demo.sh 2>/dev/null

# 4. 불완전한 SPIRE patch 파일 삭제
echo -e "${RED}삭제: spire/spiffe-helper-patch.yaml${NC}"
rm -f spire/spiffe-helper-patch.yaml
git rm -f spire/spiffe-helper-patch.yaml 2>/dev/null

# 5. 빈 cluster 디렉토리 제거
if [ -d "cluster" ] && [ -z "$(ls -A cluster)" ]; then
    echo -e "${RED}삭제: 빈 cluster/ 디렉토리${NC}"
    rmdir cluster
fi

# 6. Kafka 파일 수정 (불완전한 부분 수정)
echo -e "${YELLOW}수정: services/kafka/kafka.yaml 완성${NC}"
cat >> services/kafka/kafka.yaml <<'EOF'
        storageClassName: gp3
        resources:
          requests:
            storage: 20Gi
EOF

# 7. README.md 수정 제안
echo -e "${YELLOW}권장: README.md 파일 재작성 필요${NC}"

# 8. 파일 구조 정리
echo -e "${GREEN}✅ 현재 파일 구조:${NC}"
tree -I '.git|node_modules' 2>/dev/null || find . -type f -name "*.yaml" -o -name "*.yml" | grep -v ".git" | sort

# 9. Git 상태 확인
echo -e "${YELLOW}📊 변경사항:${NC}"
git status --short

# 10. 커밋
echo -e "${GREEN}📝 커밋 준비...${NC}"
git add -A
git commit -m "🧹 chore: 2차 정리 - 중복 파일 및 테스트 파일 제거

- cluster/eks-cluster.yaml 삭제 (깨진 파일, services/ 디렉토리와 중복)
- docker-compose.yaml 삭제 (로컬 개발용)
- spire-security-demo.sh 삭제 (테스트 스크립트)
- spire/spiffe-helper-patch.yaml 삭제 (불완전한 patch 파일)
- services/kafka/kafka.yaml 수정 (불완전한 부분 완성)

남은 파일들은 실제 K8s 배포에 필요한 핵심 매니페스트만 유지"

# 11. Push
echo -e "${YELLOW}Push 하시겠습니까? (y/n)${NC}"
read -r response
if [[ "$response" == "y" ]]; then
    git push origin main
    echo -e "${GREEN}✅ 2차 정리 완료!${NC}"
fi