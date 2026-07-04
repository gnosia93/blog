#!/bin/bash

# ================= 설정 변수 ========================
REGION="ap-northeast-2"      # 서울 리전
KEY_NAME="aws-kp-2"          # 본인의 EC2 키페어 이름 입력
# ==================================================

# 💡 핵심 함수: 인스턴스 타입과 아키텍처 타입을 받아 EC2를 띄우는 함수
launch_ec2_instance() {
    local INSTANCE_TYPE=$1
    local ARCH=$2  # "x86_64" 또는 "arm64"
    local TAG_NAME=$3

    echo "🔍 [${INSTANCE_TYPE}]용 최신 Amazon Linux 2023 (${ARCH}) AMI ID 조회 중..."
    
    # 아키텍처에 맞는 SSM 파라미터 경로 설정
    local AMI_ID=$(aws ssm get-parameters \
        --names "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${ARCH}" \
        --region "$REGION" \
        --query "Parameters[0].Value" \
        --output text)

    echo "🎯 할당된 AMI ID: ${AMI_ID}"
    echo "🚀 [${INSTANCE_TYPE}] 인스턴스 생성 시작..."

    # 인스턴스 생성 및 ID 반환
    local INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG_NAME}}]" \
        --query "Instances[0].InstanceId" \
        --output text)

    # 상위 스크립트에서 ID를 쓸 수 있도록 출력(Return 대용)
    echo "$INSTANCE_ID"
}

# ================= 메인 실행 로직 =================

# 사용자 입력 인수(Arguments) 체크
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ 사용법 오류!"
    echo "👉 사용법: $0 [첫번째 인스턴스 타입] [두번째 인스턴스 타입]"
    echo "👉 예시: $0 c6i.2xlarge c7g.2xlarge"
    exit 1
fi

TYPE_1=$1
TYPE_2=$2

echo "=================================================="
echo "🎬 멀티 아키텍처 인프라 생성을 시작합니다."
echo "   - 대상 1: $TYPE_1"
echo "   - 대상 2: $TYPE_2"
echo "=================================================="

# 1. 첫 번째 인스턴스 아키텍처 판별 (타입 이름에 'g'가 들어가면 보통 그라비톤 ARM)
# (예: c7g, m6g 등은 arm64 / c6i, m6i 등은 x86_64)
if [[ "$TYPE_1" == *g.* ]]; then ARCH_1="arm64"; else ARCH_1="x86_64"; fi
ID_1=$(launch_ec2_instance "$TYPE_1" "$ARCH_1" "Bench-${TYPE_1}")

echo "--------------------------------------------------"

# 2. 두 번째 인스턴스 아키텍처 판별 및 생성
if [[ "$TYPE_2" == *g.* ]]; then ARCH_2="arm64"; else ARCH_2="x86_64"; fi
ID_2=$(launch_ec2_instance "$TYPE_2" "$ARCH_2" "Bench-${TYPE_2}")

echo "--------------------------------------------------"
echo "⏳ 두 인스턴스가 모두 생성되었습니다. 부팅 및 퍼블릭 IP 할당을 대기합니다..."

# 두 대가 모두 running 상태가 될 때까지 동시 대기
aws ec2 wait instance-running --instance-ids "$ID_1" "$ID_2" --region "$REGION"

# 각각의 퍼블릭 IP 추출
IP_1=$(aws ec2 describe-instances --instance-ids "$ID_1" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
IP_2=$(aws ec2 describe-instances --instance-ids "$ID_2" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# ================= 최종 결과 리포트 =================
echo "=================================================="
echo "🎉 [인프라 생성 완료 리포트] 🎉"
echo "=================================================="
echo "🖥️  1. 인스턴스 ($TYPE_1 / $ARCH_1)"
echo "   - ID   : $ID_1"
echo "   - IP   : $IP_1"
echo "   - 접속 : ssh -i ${KEY_NAME}.pem ec2-user@${IP_1}"
echo "--------------------------------------------------"
echo "🖥️  2. 인스턴스 ($TYPE_2 / $ARCH_2)"
echo "   - ID   : $ID_2"
echo "   - IP   : $IP_2"
echo "   - 접속 : ssh -i ${KEY_NAME}.pem ec2-user@${IP_2}"
echo "=================================================="
