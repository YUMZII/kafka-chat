#!/bin/bash

# 첫 번째 인자: 서비스 이름 (frontend, backend, all)
SERVICE=$1

# 두 번째 인자: 버전
VERSION=$2

# 인자가 비었는지 확인
if [ -z "$SERVICE" ] || [ -z "$VERSION" ]; then
  echo "에러: 서비스명과 버전을 모두 입력해야 합니다."
  echo "사용법: ./build_push.sh <frontend|backend|all> <버전>"
  exit 1
fi

# frontend 빌드 함수
build_frontend() {
  echo "🚀 frontend 빌드 시작..."
  docker build -t frontend:$VERSION -f frontend/Dockerfile ./frontend
  docker tag frontend:$VERSION iiilee0907/frontend-ec2:latest
  docker push iiilee0907/frontend-ec2:latest
  echo "✅ frontend 빌드/푸시 완료: frontend:$VERSION -> iiilee0907/frontend-ec2:latest"
}

# backend 빌드 함수
build_backend() {
  echo "🚀 backend 빌드 시작..."
  docker build -t test-backend:$VERSION -f backend/Dockerfile ./backend
  docker tag test-backend:$VERSION iiilee0907/chat-backend-ec2:latest
  docker push iiilee0907/chat-backend-ec2:latest
  echo "✅ backend 빌드/푸시 완료: test-backend:$VERSION -> iiilee0907/chat-backend-ec2:latest"
}

# 서비스에 따라 분기
if [ "$SERVICE" == "frontend" ]; then
  build_frontend

elif [ "$SERVICE" == "backend" ]; then
  build_backend

elif [ "$SERVICE" == "all" ]; then
  build_frontend
  build_backend

else
  echo "에러: 서비스명은 frontend, backend, all 중 하나여야 합니다."
  exit 1
fi
