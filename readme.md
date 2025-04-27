  kafak-stash 생성 순서
  1. kafka key생성: kubectl apply -f kafka/kafka-key.yaml
  2. kafka stash config 설정: kubectl apply -f kafka-stash/kafka-chat-logstash-config.yaml
  3. kafka satsh deploy 배포: kubectl apply -f kafka-stash/kafka-chat-logstash-deployment.yaml