# 📨 Kafka Chat Application on Kubernetes (EC2 기반)

이 프로젝트는 **Kafka 기반 실시간 채팅 웹 애플리케이션**을 **EC2에서 구성한 Kubernetes 클러스터**에 배포하는 과정을 다룹니다.  
React(프론트엔드) + Spring Boot(백엔드) + Kafka + ELK(Logstash → Elasticsearch → Kibana) 스택을 활용합니다.

> ✅ 본 문서는 `ec2_version` 브랜치를 기준으로 작성되었습니다.

---

## 📁 프로젝트 구조

```
├── provisioner/                # StorageClass 및 RBAC 정의
├── backend/                    # Spring Boot 애플리케이션
│   ├── Dockerfile              # 백엔드 Dockerfile
│   └── k8s/                    # 백엔드 매니페스트
├── frontend/                   # React 애플리케이션
│   ├── Dockerfile              # 프론트엔드 Dockerfile
│   └── k8s/                    # 프론트엔드 매니페스트
├── kafka-stash/               # Logstash 관련 설정
├── auto-kafka.sh              # Kafka 자동 설치 스크립트
├── docker-build.sh            # Docker 이미지 자동 빌드 스크립트
```

---

## ✅ 1. Provisioner 설정 (StorageClass 및 RBAC)

Kafka PVC를 사용하기 위해 다음 명령어를 실행합니다:

```bash
kubectl apply -f provisioner/class.yaml
kubectl apply -f provisioner/rbac.yaml
kubectl apply -f provisioner/deployment.yaml
```

---

## 🚀 2. Kafka 설치 스크립트 실행

Kafka를 Helm 차트를 이용해 자동 설치합니다:

```bash
./auto-kafka.sh
```

1. Kafka 배포전 StorageClass가 잘 구성되어있는지 확인
2. bitnami/kafka` Helm 차트를 기반으로 설치 (인증정보 고정값)
3. password를 Secret 리소스를 통해 관리
4. Kafka client를 생성 후 인증 정보를 내부에 넣어준다

---

## 🐳 3. Docker 이미지 자동 빌드 (프론트 / 백엔드)

프론트엔드 혹은 백엔드의 Docker 이미지를 빌드합니다:

```bash
# 프론트엔드 빌드 (예: v1.0)
./docker-build.sh frontend 1.0

# 백엔드 빌드 (예: v1.0)
./docker-build.sh backend 1.0

# 전체 빌드 (예: v1.0)
./docker-build.sh all 1.0
```

- `{front|back|all}` 중 하나를 선택하고 `{version}` 태그를 붙이면 해당 Dockerfile로 이미지를 빌드합니다.

---

## 🧩 4. 백엔드 매니페스트 배포

Spring Boot Kafka 서버를 Kubernetes에 배포합니다:

```bash
kubectl apply -f backend/k8s/backend-service.yml
kubectl apply -f backend/k8s/backend-deployment.yml
```

---

## 🖼️ 5. 프론트엔드 매니페스트 배포

React 프론트엔드 앱을 Kubernetes에 배포합니다:

```bash
kubectl apply -f frontend/k8s/frontend-service.yml
kubectl apply -f frontend/k8s/frontend-deployment.yml
```

---

## 📦 6. Kafka 로그 수집 구성 (Logstash → Elasticsearch)

> 💡 사전 조건: Elasticsearch 및 Kibana가 먼저 설치되어 있어야 합니다.

```bash
# Logstash 설정 ConfigMap 적용
kubectl apply -f kafka-stash/kafka-chat-logstash-config.yaml

# Logstash Deployment 배포
kubectl apply -f kafka-stash/kafka-chat-logstash-deployment.yaml
```

- Kafka의 채팅 로그가 Logstash를 통해 Elasticsearch에 전달됩니다.
- Kibana에서 시각화할 수 있습니다.

---

---

## 🔐 Kafka 인증 정보 - Secret 연동 방식

Spring Boot 애플리케이션이 Kafka와 보안 연결(SCRAM-SHA-256)을 하기 위해 인증 정보를 환경변수로 받아오는 방식입니다.

`application.yml` 예시:

```yaml
spring:
  kafka:
    bootstrap-servers: kafka:9092  # Helm으로 설치된 Kafka 서비스 주소
    consumer:
      group-id: chat-group
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
    properties:
      security.protocol: SASL_PLAINTEXT
      sasl.mechanism: SCRAM-SHA-256
      sasl.jaas.config: >
        org.apache.kafka.common.security.scram.ScramLoginModule required
        username="${KAFKA_USERNAME}"
        password="${KAFKA_PASSWORD}";
```

---

### 📌 핵심 포인트

- `username`과 `password`는 **직접 하드코딩하지 않고 환경변수로 참조**합니다.
- 해당 환경변수는 Kubernetes `Secret`을 사용하여 관리합니다.
- `Deployment` 리소스에서 `env` 필드를 통해 애플리케이션 컨테이너에 주입됩니다.

---

### 🛡️ Kubernetes Secret 정의 예시

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kafka-credentials
type: Opaque
data:
  username: dXNlcjE=        # user1를 base64로 인코딩한 값
  password: dnlKZVc5STZxdg==
  # kubectl get secret kafka-user-passwords --namespace default -o jsonpath='{.data.client-passwords}' | base64 -d | cut -d , -f 1
  # 위의 명령어를 치고 나온 password값(tZES4Txl4T)을 인코딩한다
  # echo -n 'tZES4Txl4T' | base64
```

---

### 🧩 Backend Deployment에 환경변수 주입 예시

```yaml
env:
  - name: KAFKA_USERNAME
    valueFrom:
      secretKeyRef:
        name: kafka-credentials
        key: username
  - name: KAFKA_PASSWORD
    valueFrom:
      secretKeyRef:
        name: kafka-credentials
        key: password
```
- 백엔드 컨테이너가 기동될 때, 해당 Secret 값이 환경변수로 주입됩니다.


