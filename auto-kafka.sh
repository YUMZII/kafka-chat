#!/bin/bash

# ❌ 인자 체크 삭제됨 (버전 번호 필요 없음)

# 1. Kafka Helm Release 삭제
echo "👉 Helm kafka 삭제 중..."
helm uninstall kafka || true

# 2. Kafka PVC, PV 삭제
echo "👉 Kafka PVC, PV 삭제 중..."
kubectl delete pvc -n default -l app.kubernetes.io/name=kafka --ignore-not-found
kubectl delete pv -l app.kubernetes.io/name=kafka --ignore-not-found

# 3. Kafka Service 삭제
echo "👉 Kafka Service 삭제 중..."
kubectl delete svc kafka -n default --ignore-not-found

# 4. PVC, PV, Service 완전 삭제 대기
echo "👉 Kafka PVC, PV, Service 삭제 완료 대기 중..."
while true; do
  KAFKA_PVC_COUNT=$(kubectl get pvc -n default -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | wc -l)
  KAFKA_PV_COUNT=$(kubectl get pv -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | wc -l)
  KAFKA_SVC_EXIST=$(kubectl get svc kafka -n default --ignore-not-found | grep kafka | wc -l)
  
  if [ "$KAFKA_PVC_COUNT" -eq 0 ] && [ "$KAFKA_PV_COUNT" -eq 0 ] && [ "$KAFKA_SVC_EXIST" -eq 0 ]; then
    echo "✅ PVC, PV, Service 모두 삭제 완료."
    break
  else
    echo "⌛ PVC 남은 수: $KAFKA_PVC_COUNT, PV 남은 수: $KAFKA_PV_COUNT, Service 남음: $KAFKA_SVC_EXIST ... 3초 후 재확인"
    sleep 3
  fi
done

# 5. nfs-client-provisioner Pod가 Running인지 확인
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

# 6. Helm kafka 설치
echo "👉 Helm kafka 재설치 시작..."
helm install kafka bitnami/kafka \
  --set replicaCount=1 \
  --set global.defaultStorageClass=nfs-client

# 7. Kafka 설치 완료 대기 (10초 정도)
echo "👉 Kafka 설치 완료 대기 중... (10초)"
sleep 20

# 8. Kafka 비밀번호 추출
echo "👉 Kafka 비밀번호 추출 중..."
KAFKA_PASSWORD=$(kubectl get secret kafka-user-passwords --namespace default -o jsonpath='{.data.client-passwords}' | base64 -d | cut -d , -f 1)

echo "✅ 평문 Kafka 비밀번호 획득: $KAFKA_PASSWORD"

# 9. base64 인코딩
KAFKA_PASSWORD_BASE64=$(echo -n "$KAFKA_PASSWORD" | base64)
echo "✅ Base64 인코딩 비밀번호: $KAFKA_PASSWORD_BASE64"

# 10. backend application.yml 수정 (password=... 부분만)
echo "👉 backend application.yml 비밀번호 수정 중..."
sed -i "s/password=\".*\";/password=\"$KAFKA_PASSWORD\";/" ./backend/src/main/resources/application.yml

# 11. kafka-key.yaml 수정
echo "👉 kafka-key.yaml 비밀번호(base64) 수정 중..."
sed -i "s/password: .*/password: $KAFKA_PASSWORD_BASE64/" ./kafka/kafka-key.yaml

# 12. kafka-key.yaml Kubernetes 적용
echo "👉 kafka-key.yaml Kubernetes에 적용 중..."
kubectl delete -f ./kafka/kafka-key.yaml
kubectl apply -f ./kafka/kafka-key.yaml

# 13. kafka-credentials Secret 생성 확인
echo "👉 kafka-credentials Secret 생성 확인 중..."
sleep 2

KAFKA_SECRET_EXIST=$(kubectl get secret kafka-credentials -n logging --ignore-not-found | grep kafka-credentials | wc -l)

if [ "$KAFKA_SECRET_EXIST" -eq 1 ]; then
  echo "✅ kafka-credentials Secret 정상 생성됨!"
else
  echo "❌ kafka-credentials Secret 생성 실패. 확인 필요!"
  exit 1
fi

# 14. (❌ Backend Docker 빌드 제거됨)

echo "🎉 모든 작업 완료!"

# ✅ 추가: client.properties password 수정
echo "👉 client.properties password 수정 중..."
sed -i "s/password=\".*\";/password=\"$KAFKA_PASSWORD\";/" client.properties
echo "✅ client.properties 파일 수정 완료!"

# ✅ 추가: kafka-client Pod 생성
echo "👉 kafka-client Pod 생성 중..."
kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:4.0.0-debian-12-r0 --namespace default --command -- sleep infinity

# ✅ 추가: kafka-client Pod Running 대기
echo "👉 kafka-client Pod가 Running 상태가 될 때까지 대기 중..."
while true; do
  POD_STATUS=$(kubectl get pod kafka-client -n default -o jsonpath='{.status.phase}')
  if [ "$POD_STATUS" = "Running" ]; then
    echo "✅ kafka-client Pod가 Running 상태입니다."
    break
  else
    echo "⌛ 현재 kafka-client 상태: $POD_STATUS ... 3초 후 재확인"
    sleep 3
  fi
done

# ✅ 추가: client.properties 파일 복사
echo "👉 client.properties 파일을 kafka-client Pod로 복사 중..."
kubectl cp --namespace default client.properties kafka-client:/tmp/client.properties

echo "🎉 추가 작업까지 모두 완료!"
