## AWS Graviton 으로 EKS 비용 최적화 하기 ##

최근 인프라 비용 절감과 성능 향상을 위해 AWS EKS(Elastic Kubernetes Service)에서 ARM64 기반의 AWS Graviton 인스턴스를 도입하는 기업이 급격히 늘고 있습니다.
Graviton은 기존 x86 인스턴스 대비 최대 40%의 가성비 향상을 제공하지만, 이를 EKS에 성공적으로 적용하려면 멀티 아키텍처(Multi-Architecture) 컨테이너 이미지 빌드가 필요합니다.
쿠버네티스 클러스터가 x86(AMD64)과 ARM64 노드를 동시에 사용하는 하이브리드 환경이거나, 기존 x86에서 ARM64로 점진적 전환을 시도할 때,
하나의 이미지 태그로 두 아키텍처를 모두 지원하는 멀티 아키텍처 이미지는 필수적입니다.

이 블로그 포스트에서는 Docker의 Buildx와 **AWS 가상 환경(GitHub Actions / 로컬)**을 활용하여 EKS에서 완벽하게 동작하는 멀티 아키텍처 이미지를 빌드하고 Amazon ECR에 배포하는 방법을 알아보겠습니다.

### 1. 멀티 아키텍처 이미지란? ###

멀티 아키텍처(Multi-Architecture) 이미지란, 하나의 이미지 태그(예: my-app:v1.0.0) 안에 여러 종류의 CPU 아키텍처(예: Intel/AMD의 x86_64, 애플 실리콘이나 AWS Graviton의 ARM64 등)에서 실행할 수 있는 바이너리들을 모두 포함하고 있는 컨테이너 이미지를 말합니다.   
예전에는 대부분의 서버와 PC가 Intel/AMD 기반의 x86(amd64) 아키텍처를 사용했기 때문에 아키텍처를 신경 쓸 필요가 없었습니다. 하지만 최근 몇 년 사이에
개발자들이 사용하는 맥북이 Intel에서 ARM 기반의 M1/M2/M3/M4(arm64) 칩셋으로 바뀌었고, AWS(Graviton 인스턴스)를 비롯한 Google Cloud, Azure 등에서 가성비와 전력 효율이 압도적인 ARM 기반 서버를 대거 도입하기 시작했습니다.
만약 x86 환경에서 빌드한 일반 이미지를 ARM 기반의 맥북이나 AWS Graviton 서버에서 실행하면 exec format error 같은 에러가 나면서 컨테이너가 뻗어버립니다. CPU가 이해할 수 없는 언어로 작성된 명령어이기 때문입니다. 멀티 아키텍처 이미지는 이 문제를 깔끔하게 해결해 줍니다.

_그림추가_

Docker에서 멀티 아키텍처 이미지는 두 아키텍처의 바이너리를 한 파일에 뭉쳐놓은 것이 아닙니다. AMD64용 이미지와 ARM64용 이미지를 각각 빌드한 뒤, 이를 하나의 **매니페스트 리스트(Manifest List)**로 묶어주는 개념입니다.
EKS 노드가 이미지를 풀(Pull)할 때, 컨테이너 런타임(containerd)이 노드의 아키텍처(예: linux/amd64 또는 linux/arm64)를 확인하고, 매니페스트 리스트를 참조하여 해당 노드에 맞는 정확한 레이어만 다운로드합니다. 따라서 개발자나 배포 매니페스트(YAML) 입장에서는 기존과 동일하게 단 하나의 이미지 태그만 관리하면 됩니다.

### 2. Docker Buildx 준비하기 ###
멀티 아키텍처 빌드를 가장 편하게 수행할 수 있는 도구는 Docker 공식 확장 기능인 Buildx입니다. Buildx는 내부적으로 툴킷인 BuildKit을 사용하며, QEMU 에뮬레이터를 통해 로컬 환경(예: Intel 맥북 또는 Windows PC)에서도 ARM64 이미지를 교차 빌드(Cross-compile)할 수 있게 해줍니다.
로컬 환경 설정 (Linux / macOS 기준)
	
#### 1.	Docker 빌더 상태 확인 및 QEMU 에뮬레이터 설치 ####
멀티 아키텍처 빌드를 지원하는 QEMU 바이너리를 등록합니다.
```
docker run --privileged --rm tonistiigi/binfmt --install all
```

#### 2.	새로운 Buildx 드라이버 생성 및 활성화 ####
기본(default) 빌더는 멀티 플랫폼 빌드를 지원하지 않으므로, docker-container 드라이버를 사용하는 새 빌더를 만듭니다.
```
docker buildx create --name eks-builder --use
docker buildx inspect --bootstrap
```
지원 플랫폼 목록에 linux/amd64와 linux/arm64가 모두 표시되면 준비 완료입니다.

#### 3. 멀티 아키텍처 Dockerfile 작성 팁 ####
Dockerfile을 작성할 때 가장 중요한 것은 베이스 이미지(Base Image)가 멀티 아키텍처를 지원하는지 확인하는 것입니다. 예를 들어 ubuntu, alpine, node, openjdk 등 공식 이미지들은 대부분 두 아키텍처를 모두 지원합니다.
또한, Go나 Rust 같은 컴파일 언어는 멀티 스테이지 빌드(Multi-stage Build)를 활용하면 에뮬레이션 아키텍처 컴파일 단계를 생략하고 네이티브 속도로 교차 컴파일을 수행할 수 있어 빌드 시간이 대폭 단축됩니다.

##### Go 언어 멀티 스테이지 Dockerfile 예시 ####

```
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
```

#### 4. 실전: AWS ECR로 멀티 아키텍처 이미지 빌드 및 푸시 ####
이제 준비된 Buildx를 사용해 빌드와 동시에 AWS ECR(Elastic Container Registry)로 푸시해 보겠습니다. 멀티 아키텍처 이미지는 로컬 도커 데몬 저장소에 한 번에 저장할 수 없으므로, 빌드와 동시에 레지스트리로 바로 푸시(--push)하는 것이 표준 워크플로우입니다.
```
# 1. AWS ECR 로그인인
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

# 2. Buildx를 활용한 멀티 플랫폼 빌드 및 푸시
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/my-eks-app:v1.0.0 \
  --push .
```
푸시가 완료된 후 AWS ECR 콘솔에 접속해 보면, 하나의 태그(v1.0.0) 아래에 Defined 2 artifacts 형태로 **Image Index(Manifest List)**가 생성되어 있고, 그 하위에 아키텍처별로 별도의 이미지 아티팩트가 매핑되어 있는 것을 확인할 수 있습니다.

#### 5. CI/CD 파이프라인 연동 (GitHub Actions 예시) ####
실무에서는 로컬보다 GitHub Actions 같은 CI/CD 툴을 많이 사용합니다. 아래는 GitHub Actions에서 멀티 아키텍처 이미지를 빌드하여 ECR에 배포하는 표준 워크플로우 예시입니다.
```
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
```

#### 6. EKS 배포 시 주의할 점 (Node Selector & Toleration) ####
멀티 아키텍처 이미지 배포 준비가 끝났다면, 이제 EKS 클러스터가 Graviton 노드를 올바르게 스케줄링할 수 있도록 배포 매니페스트(YAML)를 구성해야 합니다.
만약 클러스터 내에 x86 노드그룹과 Graviton(ARM64) 노드그룹이 혼재되어 있다면, 쿠버네티스의 내장 라벨인 kubernetes.io/arch를 활용하여 파드가 원하는 아키텍처 노드로 찾아가도록 제어할 수 있습니다.

#### 특정 아키텍처 선호 설정 (Node Affinity 예시) ####
```
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
```

### 마치며 ###
AWS Graviton 인스턴스는 대규모 EKS 클러스터를 운영하는 기업에게 가장 매력적인 비용 절감 카드 중 하나입니다. 오늘 살펴본 Docker Buildx를 활용한 멀티 아키텍처 이미지 빌드 파이프라인을 한 번 구축해 두면, 인프라 변경에 유연하게 대응하면서 서비스 중단 없이 안전하게 ARM64 아키텍처로 전환을 완수할 수 있습니다.
지금 바로 파이프라인에 Buildx 스텝을 추가하고, EKS의 컴퓨팅 가성비를 극대화해 보세요!

```




---
앞에서 설명해 드린 docker-container 드라이버에 binfmt를 등록해서 쓰는 방식은 QEMU 에뮬레이터(Emulator) 기반의 빌드입니다.
x86 컴퓨터가 ARM64 명령어 세트를 소프트웨어적으로 흉내(에뮬레이션) 내서 빌드하는 방식이죠. 편리하긴 하지만, 자바나 가상머신 기반 언어, 무거운 컴파일이 필요한 환경에서는 빌드 속도가 5배에서 10배 이상 느려지는 치명적인 단점이 있습니다.

이 속도 문제를 극복하기 위한 네이티브(Native) 빌드 방식은 크게 두 가지로 나뉩니다. 

#### 1. 네이티브 빌드 ####
이 방식은 에뮬레이션을 쓰지 않고, 실제 ARM64 하드웨어(예: AWS Graviton 인스턴스 또는 ARM 기반 인스턴스)를 Docker Buildx의 원격 노드(Worker)로 등록해서 각자 자기 아키텍처에 맞는 빌드를 진짜 '네이티브'하게 수행하는 방식입니다.

#### 🛠️ 아키텍처 및 설정 원리 ####
```
Docker Buildx는 원격에 있는 다른 Docker 데몬을 하나의 빌더 그룹으로 묶을 수 있습니다.
	1.	원격 ARM 서버 준비: AWS에 아주 저렴한 Graviton(ARM64) EC2 인스턴스를 하나 띄우고 Docker를 설치합니다.
	2.	원격 노드 연결: 로컬(x86)이나 CI/CD 서버에서 SSH를 통해 원격 ARM 서버를 Buildx 빌더로 추가합니다.
# x86 로컬 호스트와 원격 ARM64 서버를 하나의 빌더(my-native-builder)로 묶기
docker buildx create --name my-native-builder --node local_x86 context default
docker buildx create --name my-native-builder --node remote_arm64 ssh://ubuntu@<ARM_SERVER_IP> --append --use

	3.	빌드 실행: 이 상태에서 docker buildx build --platform linux/amd64,linux/arm64 ... 명령을 내리면, Buildx가 영리하게 amd64 레이어는 로컬 x86에서, arm64 레이어는 SSH로 연결된 원격 Graviton 서버로 보내서 100% 네이티브 속도로 빌드한 뒤 결과물만 ECR로 전송합니다.
•	장점: 에뮬레이터 오버헤드가 0%이므로 가장 빠르고 안정적입니다.
•	단점: 빌드용 ARM 서버(인스턴스)를 따로 띄우고 관리해야 하므로 추가 비용과 인프라 관리가 필요합니다.
```

#### 2. 언어 특징을 활용한 교차 컴파일: "멀티 스테이지 빌드" ####
만약 컴파일 언어(Go, Rust, C++ 등)를 사용하신다면, 굳이 ARM 서버를 따로 띄우지 않고도 **Dockerfile 내부에서 네이티브 속도로 교차 컴파일(Cross-Compilation)**을 수행할 수 있습니다.

#### 🛠️ 작동 원리 (Go 언어 예시) ####
Go 언어는 내부적으로 컴파일러가 강력해서, x86 CPU 아키텍처 위에서도 명령어 한 줄(GOARCH=arm64)만 주면 ARM64용 바이너리를 네이티브 속도로 아주 빠르게 뽑아낼 수 있습니다. 이를 Dockerfile의 멀티 스테이지에 녹여내는 것입니다.
```
# 1단계: 빌드 스테이지 (호스트의 네이티브 아키텍처를 그대로 사용함)
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS builder

WORKDIR /app
COPY . .

# Buildx가 자동으로 주입해주는 타겟 플랫폼 변수
ARG TARGETOS
ARG TARGETARCH

# 🔥 핵심: QEMU를 안 쓰고, x86 엔진으로 Go 컴파일러를 돌려 ARM64 바이너리를 초고속 추출
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o main .

# 2단계: 최종 실행 스테이지 (가벼운 배포용 타겟 이미지)
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .

CMD ["./main"]
```
•	동작 방식: 빌드 환경 자체(--platform=$BUILDPLATFORM)를 현재 빌드를 돌리는 컴퓨터(x86)와 일치시킵니다. 따라서 빌드 컨테이너 안에서 명령어를 실행할 때 에뮬레이터를 거치지 않아 속도가 일반 빌드와 똑같이 빠릅니다. 오직 결과물 바이너리만 ARM64용으로 뱉어낼 뿐입니다.
•	장점: 별도의 ARM 인프라 구축 없이 Dockerfile 수정만으로 폭발적인 속도 향상을 얻을 수 있습니다.
•	단점: Go, Rust 등 교차 컴파일을 원천 지원하는 일부 언어에만 제한적으로 사용할 수 있습니다. (Java/Spring 같은 환경이나 복잡한 C 라이브러리 의존성이 있으면 적용하기 까다롭습니다.)

| 비교 항목 | 1. QEMU 에뮬레이터 방식 (이전 방식) | 2. 원격 노드 네이티브 방식 | 3. 교차 컴파일 방식 |
| :--- | :--- | :--- | :--- |
| **빌드 속도** | 🐌 매우 느림 (에뮬레이션 부하) | ⚡ 매우 빠름 (네이티브) | ⚡ 매우 빠름 (네이티브) |
| **인프라 구축** | 필요 없음 (로컬에서 끝) | 🛠️ ARM 서버 추가 구축 필요 | 필요 없음 (Dockerfile만 수정) |
| **언어 제약** | 없음 (모든 언어 가능) | 없음 (모든 언어 가능) | ⚠️ Go, Rust 등 컴파일 언어 위주 |

---

## 깃허브 액션 - 멀티 아키텍처 이미지 빌드하기 ##
GitHub Actions에서 에뮬레이터(QEMU) 없이 100% 네이티브 속도로 멀티 아키텍처 이미지를 빌드하려면, GitHub Actions가 돌아가는 기본 주자(x86_64) 외에 **ARM64 전용 자체 호스트 주자(Self-hosted Runner)**를 파이프라인에 함께 엮어야 합니다.
이를 구현하는 가장 세련된 방법은 GitHub Actions의 행렬(Matrix) 빌드를 활용하는 것입니다. x86 노드와 ARM64 노드에서 각각 이미지를 네이티브하게 빌드하여 ECR로 푸시한 뒤, 마지막 단계에서 두 이미지를 하나의 매니페스트 리스트(Manifest List)로 묶어주는 방식입니다.
AWS 환경(EC2 또는 AWS CodeBuild ephemeral runner)에 x86_64 주자와 ARM64 주자가 각각 준비되어 있다고 가정하고 작성된 실전 워크플로우 스크립트입니다.
🛠️ GitHub Actions 네이티브 멀티 아키텍처 빌드 스크립트 (.github/workflows/native-multi-arch.yml)

```
name: Native Multi-Architecture Build

on:
  push:
    branches: [ "main" ]

env:
  AWS_REGION: ap-northeast-2
  ECR_REPOSITORY: my-eks-app
  IMAGE_TAG: ${{ github.sha }}

jobs:
  # 1단계: 각 아키텍처별 환경에서 네이티브 빌드 후 개별 태그로 푸시
  build-native:
    name: Build Native Image
    runs-on: ${{ matrix.runner-os }}
    strategy:
      matrix:
        # self-hosted 레이블은 각각 x86_64와 ARM64 가상머신에 매핑되어 있어야 합니다.
        include:
          - runner-os: [self-hosted, linux, x64]
            arch: amd64
          - runner-os: [self-hosted, linux, arm64]
            arch: arm64
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    # QEMU 설정 단계가 없으므로 해당 장비의 CPU를 그대로 사용하는 100% 네이티브 빌드입니다.
    - name: Build and Push Architecture-Specific Image
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/${{ matrix.arch }}
        push: true
        tags: ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ env.IMAGE_TAG }}-${{ matrix.arch }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  # 2단계: 개별 아키텍처 이미지를 하나의 멀티 아키텍처 매니페스트로 결합
  create-manifest:
    name: Create Multi-Arch Manifest
    needs: build-native
    runs-on: ubuntu-latest # 매니페스트 결합은 메타데이터 작업이라 아무 호스트에서나 해도 빠릅니다.
    steps:
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    # docker buildx imagetools 명령을 사용하여 이미 푸시된 두 이미지를 하나의 태그로 묶어줍니다.
    - name: Create and Push Manifest List
      run: |
        REGISTRY=${{ steps.login-ecr.outputs.registry }}
        REPO=${{ env.ECR_REPOSITORY }}
        TAG=${{ env.IMAGE_TAG }}
        
        docker buildx imagetools create -t $REGISTRY/$REPO:$TAG \
          $REGISTRY/$REPO:${TAG}-amd64 \
          $REGISTRY/$REPO:${TAG}-arm64
```

파이프라인 작동 메커니즘 설명
	1.	matrix를 통한 병렬 처리: build-native 작업이 시작되면 x86 주자와 ARM64 주자에서 각각 독립적으로 빌드가 동시에 돌아갑니다. 에뮬레이터 오버헤드가 전혀 없기 때문에 각 아키텍처의 최대 속도로 빌드가 완료됩니다.
	2.	임시 태그 푸시: x86 장비는 빌드 후 이미지 뒤에 -amd64를 붙여서 ECR에 올리고, ARM64 장비는 -arm64를 붙여서 올립니다.
	3.	docker buildx imagetools create (핵심): 마지막 create-manifest 단계에서 ECR에 이미 올라가 있는 두 개별 이미지의 매니페스트를 다운받아, 하나의 통합 태그(${{ env.IMAGE_TAG }})를 가진 **매니페스트 리스트(Manifest List)**로 재조립하여 ECR에 최종 배포합니다.
이 방식을 쓰면 대규모 프로젝트나 무거운 의존성을 가진 어플리케이션도 CI/CD 빌드 타임을 x86 단독 빌드 수준으로 극적으로 유지할 수 있습니다! 

