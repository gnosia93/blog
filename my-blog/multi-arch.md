## AWS Graviton 도입을 위한 EKS 멀티 아키텍처 컨테이너 이미지 빌드 가이드 ##

최근 인프라 비용 절감과 성능 향상을 위해 AWS EKS(Elastic Kubernetes Service)에서 ARM64 기반의 AWS Graviton 인스턴스를 도입하는 기업이 급격히 늘고 있습니다.
Graviton은 기존 x86 인스턴스 대비 최대 40%의 가성비 향상을 제공하지만, 이를 EKS에 성공적으로 적용하려면 한 가지 큰 장벽을 넘어야 합니다.
바로 멀티 아키텍처(Multi-Architecture) 컨테이너 이미지 빌드입니다.
쿠버네티스 클러스터가 x86(AMD64)과 ARM64 노드를 동시에 사용하는 하이브리드 환경이거나, 기존 x86에서 ARM64로 점진적 전환을 시도할 때,
하나의 이미지 태그로 두 아키텍처를 모두 지원하는 멀티 아키텍처 이미지는 필수적입니다.

이 블로그 포스트에서는 Docker의 Buildx와 **AWS 가상 환경(GitHub Actions / 로컬)**을 활용하여 EKS에서 완벽하게 동작하는 멀티 아키텍처 이미지를 빌드하고 Amazon ECR에 배포하는 방법을 알아보겠습니다.


### 1. 멀티 아키텍처 이미지란? ###

멀티 아키텍처(Multi-Architecture) 이미지란, 하나의 이미지 태그(예: my-app:v1.0.0) 안에 여러 종류의 CPU 아키텍처(예: Intel/AMD의 x86_64, 애플 실리콘이나 AWS Graviton의 ARM64 등)에서 실행할 수 있는 바이너리들을 모두 포함하고 있는 컨테이너 이미지를 말합니다.   
예전에는 대부분의 서버와 PC가 Intel/AMD 기반의 x86(amd64) 아키텍처를 사용했기 때문에 아키텍처를 신경 쓸 필요가 없었습니다. 하지만 최근 몇 년 사이에 시장이 급변했습니다.
•	로컬 개발 환경의 변화: 개발자들이 사용하는 맥북이 Intel에서 ARM 기반의 M1/M2/M3(arm64) 칩셋으로 바뀌었습니다.
•	클라우드 인프라의 변화: AWS(Graviton 인스턴스), Google Cloud, Azure 등에서 가성비와 전력 효율이 압도적인 ARM 기반 서버를 대거 도입하기 시작했습니다.
만약 x86 환경에서 빌드한 일반 이미지를 ARM 기반의 맥북이나 AWS Graviton 서버에서 실행하면 exec format error 같은 에러가 나면서 컨테이너가 뻗어버립니다. CPU가 이해할 수 없는 언어로 작성된 명령어이기 때문입니다. 멀티 아키텍처 이미지는 이 문제를 깔끔하게 해결해 줍니다.

2. 어떻게 작동하나요? (매니페스트 리스트의 마법)
멀티 아키텍처 이미지는 두 아키텍처용 파일을 물리적으로 무식하게 한 덩어리로 합쳐놓은 것이 아닙니다.
실제로는 "매니페스트 리스트(Manifest List)" 또는 **"이미지 인덱스(Image Index)"**라는 일종의 '안내 책자' 역할을 하는 가벼운 메타데이터 파일이 최상단에 존재합니다.
	1.	빌드 단계: 개발자나 CI/CD 파이프라인이 amd64용 이미지와 arm64용 이미지를 각각 따로 빌드합니다.
	2.	패키징 단계: Docker가 이 두 이미지를 하나의 태그로 묶고, 최상단에 안내 책자(Manifest)를 붙여서 컨테이너 레지스트리(Docker Hub, AWS ECR 등)에 올립니다.
	3.	다운로드(Pull) 단계: 서버나 쿠버네티스 노드가 이 이미지를 다운로드하려고 할 때, 컨테이너 런타임이 **"어, 나 지금 AWS Graviton(ARM64) 노드인데?"**라고 레지스트리에 알립니다.
	4.	실행: 레지스트리는 안내 책자를 보고 ARM64에 해당하는 이미지 레이어만 쏙 골라서 보내줍니다.
따라서 개발자나 인프라 엔지니어는 쿠버네티스 YAML 파일이나 배포 스크립트에서 아키텍처별로 이미지 이름을 다르게 지정할 필요 없이, 기존처럼 단 하나의 이미지 이름만 사용하면 되므로 운영이 매우 단순해집니다.


_그림추가_

Docker에서 멀티 아키텍처 이미지는 두 아키텍처의 바이너리를 한 파일에 뭉쳐놓은 것이 아닙니다. AMD64용 이미지와 ARM64용 이미지를 각각 빌드한 뒤, 이를 하나의 **매니페스트 리스트(Manifest List)**로 묶어주는 개념입니다.
EKS 노드가 이미지를 풀(Pull)할 때, 컨테이너 런타임(containerd)이 노드의 아키텍처(예: linux/amd64 또는 linux/arm64)를 확인하고, 매니페스트 리스트를 참조하여 해당 노드에 맞는 정확한 레이어만 다운로드합니다. 따라서 개발자나 배포 매니페스트(YAML) 입장에서는 기존과 동일하게 단 하나의 이미지 태그만 관리하면 됩니다.

### 2. Docker Buildx 준비하기 ###
멀티 아키텍처 빌드를 가장 편하게 수행할 수 있는 도구는 Docker 공식 확장 기능인 Buildx입니다. Buildx는 내부적으로 툴킷인 BuildKit을 사용하며, QEMU 에뮬레이터를 통해 로컬 환경(예: Intel 맥북 또는 Windows PC)에서도 ARM64 이미지를 교차 빌드(Cross-compile)할 수 있게 해줍니다.
로컬 환경 설정 (Linux / macOS 기준)
	1.	Docker 빌더 상태 확인 및 QEMU 에뮬레이터 설치
멀티 아키텍처 빌드를 지원하는 QEMU 바이너리를 등록합니다.
docker run --privileged --rm tonistiigi/binfmt --install all

	2.	새로운 Buildx 드라이버 생성 및 활성화
기본(default) 빌더는 멀티 플랫폼 빌드를 지원하지 않으므로, docker-container 드라이버를 사용하는 새 빌더를 만듭니다.
docker buildx create --name eks-builder --use
docker buildx inspect --bootstrap

지원 플랫폼 목록에 linux/amd64와 linux/arm64가 모두 표시되면 준비 완료입니다.
3. 멀티 아키텍처 Dockerfile 작성 팁
Dockerfile을 작성할 때 가장 중요한 것은 베이스 이미지(Base Image)가 멀티 아키텍처를 지원하는지 확인하는 것입니다. 예를 들어 ubuntu, alpine, node, openjdk 등 공식 이미지들은 대부분 두 아키텍처를 모두 지원합니다.
또한, Go나 Rust 같은 컴파일 언어는 멀티 스테이지 빌드(Multi-stage Build)를 활용하면 에뮬레이션 아키텍처 컴파일 단계를 생략하고 네이티브 속도로 교차 컴파일을 수행할 수 있어 빌드 시간이 대폭 단축됩니다.
Go 언어 멀티 스테이지 Dockerfile 예시
# 빌드 스테이지 (컨테이너 호스트 아키텍처 활용)
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS builder

WORKDIR /app
COPY . .

# Buildx가 주입해주는 타겟 플랫폼 변수 활용
ARG TARGETOS
ARG TARGETARCH

# 네이티브 교차 컴파일 실행 (QEMU 에뮬레이션을 쓰지 않아 빠름)
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o main .

# 최종 실행 스테이지
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .

CMD ["./main"]

4. 실전: AWS ECR로 멀티 아키텍처 이미지 빌드 및 푸시
이제 준비된 Buildx를 사용해 빌드와 동시에 AWS ECR(Elastic Container Registry)로 푸시해 보겠습니다. 멀티 아키텍처 이미지는 로컬 도커 데몬 저장소에 한 번에 저장할 수 없으므로, 빌드와 동시에 레지스트리로 바로 푸시(--push)하는 것이 표준 워크플로우입니다.
# 1. AWS ECR 로그인인
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. Buildx를 활용한 멀티 플랫폼 빌드 및 푸시
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/my-eks-app:v1.0.0 \
  --push .

푸시가 완료된 후 AWS ECR 콘솔에 접속해 보면, 하나의 태그(v1.0.0) 아래에 Defined 2 artifacts 형태로 **Image Index(Manifest List)**가 생성되어 있고, 그 하위에 아키텍처별로 별도의 이미지 아티팩트가 매핑되어 있는 것을 확인할 수 있습니다.
5. CI/CD 파이프라인 연동 (GitHub Actions 예시)
실무에서는 로컬보다 GitHub Actions 같은 CI/CD 툴을 많이 사용합니다. 아래는 GitHub Actions에서 멀티 아키텍처 이미지를 빌드하여 ECR에 배포하는 표준 워크플로우 예시입니다.
name: Build and Push Multi-Arch Image to ECR

on:
  push:
    branches: [ "main" ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ap-northeast-2

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2

    # QEMU 및 Buildx 설정 (멀티 아키텍처 핵심 스텝)
    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.login-ecr.outputs.registry }}/my-eks-app:latest

6. EKS 배포 시 주의할 점 (Node Selector & Toleration)
멀티 아키텍처 이미지 배포 준비가 끝났다면, 이제 EKS 클러스터가 Graviton 노드를 올바르게 스케줄링할 수 있도록 배포 매니페스트(YAML)를 구성해야 합니다.
만약 클러스터 내에 x86 노드그룹과 Graviton(ARM64) 노드그룹이 혼재되어 있다면, 쿠버네티스의 내장 라벨인 kubernetes.io/arch를 활용하여 파드가 원하는 아키텍처 노드로 찾아가도록 제어할 수 있습니다.
특정 아키텍처 선호 설정 (Node Affinity 예시)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-eks-app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/my-eks-app:v1.0.0
      # Graviton(ARM64) 노드에 우선 배포되도록 설정
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - arm64

마치며
AWS Graviton 인스턴스는 대규모 EKS 클러스터를 운영하는 기업에게 가장 매력적인 비용 절감 카드 중 하나입니다. 오늘 살펴본 Docker Buildx를 활용한 멀티 아키텍처 이미지 빌드 파이프라인을 한 번 구축해 두면, 인프라 변경에 유연하게 대응하면서 서비스 중단 없이 안전하게 ARM64 아키텍처로 전환을 완수할 수 있습니다.
지금 바로 파이프라인에 Buildx 스텝을 추가하고, EKS의 컴퓨팅 가성비를 극대화해 보세요!

```
