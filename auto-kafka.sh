#!/bin/bash

# 인자 체크
if [ -z "$1" ]; then
  echo "❌ 에러: 백엔드 Docker 빌드용 버전 번호를 입력해야 합니다."
  echo "사용법: ./auto-kafka.sh <버전번호>"
  exit 1
fi

VERSION=$1

# 1. Kafka 관련 Helm Release 삭제
echo "👉 Helm kafka 삭제 중..."
helm uninstall kafka || true

# 2. Kafka PVC, PV 삭제
echo "👉 Kafka PVC, PV 삭제 중..."
kubectl delete pvc -n default -l app.kubernetes.io/name=kafka --ignore-not-found
kubectl delete pv -l app.kubernetes.io/name=kafka --ignore-not-found

# 3. PVC, PV 완전 삭제 대기
echo "👉 Kafka PVC, PV 삭제 완료 대기 중..."
while true; do
  PVC_COUNT=$(kubectl get pvc -n default -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | wc -l)
  PV_COUNT=$(kubectl get pv -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | wc -l)
  
  if [ "$PVC_COUNT" -eq 0 ] && [ "$PV_COUNT" -eq 0 ]; then
    echo "✅ PVC, PV 모두 삭제 완료."
    break
  else
    echo "⌛ PVC 남은 수: $PVC_COUNT, PV 남은 수: $PV_COUNT ... 3초 후 재확인"
    sleep 3
  fi
done

# 4. nfs-client-provisioner Pod가 Running인지 확인
echo "👉 nfs-client-provisioner Pod 상태 확인 중..."
while true; do
  NFS_STATUS=$(kubectl get pods -l app=nfs-client-provisioner -n default -o jsonpath='{.items[0].status.phase}')
  
  if [ "$NFS_STATUS" = "Running" ]; then
    echo "✅ nfs-client-provisioner Pod가 Running 상태입니다."
    break
  else
    echo "⌛ 현재 nfs-client-provisioner 상태: $NFS_STATUS ... 3초 후 재확인"
    sleep 3
  fi
done

# 5. Helm kafka 설치
echo "👉 Helm kafka 재설치 시작..."
helm install kafka bitnami/kafka \
  --set replicaCount=1 \
  --set global.defaultStorageClass=nfs-client

# 6. Kafka 설치 완료 대기 (10초 정도)
echo "👉 Kafka 설치 완료 대기 중... (10초)"
sleep 10

# 7. Kafka 비밀번호 추출
echo "👉 Kafka 비밀번호 추출 중..."
PASSWORD=$(kubectl get secret kafka-user-passwords --namespace default -o jsonpath='{.data.client-passwords}' | base64 -d | cut -d , -f 1)

echo "✅ 평문 비밀번호 획득: $PASSWORD"

# 8. base64 인코딩
PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64)
echo "✅ Base64 인코딩 비밀번호: $PASSWORD_BASE64"

# 9. application.yml 수정
echo "👉 backend application.yml 비밀번호 수정 중..."
sed -i "s/password: .*/password: \"$PASSWORD\"/" ./backend/src/main/resources/application.yml

# 10. kafka-key.yaml 수정
echo "👉 kafka-key.yaml 비밀번호(base64) 수정 중..."
sed -i "s/password: .*/password: $PASSWORD_BASE64/" ./kafka/kafka-key.yaml

# 11. Backend Docker 빌드
echo "👉 Backend Docker 빌드 시작..."
./docker-build.sh backend $VERSION

echo "🎉 모든 작업 완료!"
