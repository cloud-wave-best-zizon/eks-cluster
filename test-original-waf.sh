#!/bin/bash

echo "🧪 WAF 원래 설정 테스트"
echo "======================="
echo "실제 IP로 Rate Limit 테스트 (X-Forwarded-For는 ALB가 덮어씀)"
echo ""

URL="https://api.cloudwave10.shop/api/v1/health"

echo "📊 15번 요청 테스트 (Rate limit: 10/분)"
echo "----------------------------------------"

BLOCKED=0
SUCCESS=0

for i in {1..15}; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" --max-time 2)
    
    if [ "$RESPONSE" = "403" ]; then
        echo "[$i] 🚫 차단됨 (403)"
        ((BLOCKED++))
    else
        echo "[$i] ✅ 성공 ($RESPONSE)"
        ((SUCCESS++))
    fi
    
    sleep 0.5
done

echo ""
echo "📊 결과:"
echo "  성공: $SUCCESS"
echo "  차단: $BLOCKED"
echo ""

if [ $BLOCKED -gt 0 ]; then
    echo "✅ WAF가 정상적으로 작동합니다!"
    echo "   (당신의 실제 IP에 대해 Rate limit이 적용됨)"
else
    echo "📝 참고: 차단이 없다면 Rate limit이 아직 초기화되지 않았을 수 있습니다."
    echo "   1분 후 다시 테스트해보세요."
fi
