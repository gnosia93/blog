
## AWS Transform custom (ATX) 개요 ##
에이전트형 AI로 코드/라이브러리/프레임워크를 대규모로 현대화해 기술 부채를 줄이는 서비스입니다. 언어 버전 업그레이드, API/서비스 마이그레이션, 프레임워크 전환, 리팩터링, 그리고 x86 → Graviton 전환을 다룹니다 (AWS Transform 문서).

핵심 개념은 Transformation Definition(TD) 으로, "변환을 어떻게 수행할지 기술한 재사용 가능한 레시피"이며 자연어로 작성합니다 (DevOps 블로그).

### 관리형 4단계 Graviton 변환 ###
Java 애플리케이션을 x86 → Graviton으로 옮기는 관리형 변환은 다음 4단계로 진행됩니다 (Graviton Getting Started):

* 분석 (Analyze) — 아키텍처 관련 호환성 차단 요소(blocker)를 식별하고, 네이티브 라이브러리의 ARM64 지원 여부를 검증
* 수정 (Fix) — 자동 재컴파일 및 의존성 업데이트로 문제 해결. 이때 ARM64 실행을 막는 의존성만 선별적으로 업데이트
* 검증 (Validate) — 변경 사항을 실제 Graviton(ARM64) 기반 인스턴스에서 테스트
* 문서화 (Document) — 전환 내용을 기록
참고: 순수 Java는 Amazon Corretto/OpenJDK가 ARM64에 최적화되어 있어 변경이 거의 필요 없는 경우도 많고, 차단 요소는 대개 네이티브(JNI) 의존성에서 발생합니다.


## 데모 시나리오 ##
Maven 기반 Java 8 결제 배치 앱을 x86 EC2에서 돌리다가 Graviton(ARM64)으로 옮기려는 상황입니다. 이 앱은 오래된 네이티브 압축 라이브러리를 쓰고 있어 그대로는 ARM64에서 터집니다. 이게 바로 ATX가 잡아내는 전형적인 blocker입니다.

### 1. 사전 준비 ###
```
# Node.js 20+ 와 Git 필요, Windows는 WSL 사용
node -v          # v20.x
cd payments-batch
git init && git add . && git commit -m "Initial commit"   # 유효한 Git 레포여야 함
```

#### pom.xml (일부) ####
```
<dependencies>
  <!-- 이 버전 대역은 aarch64(ARM64) 네이티브 바이너리를 포함하지 않음 -> Graviton에서 UnsatisfiedLinkError -->
  <dependency>
    <groupId>org.xerial.snappy</groupId>
    <artifactId>snappy-java</artifactId>
    <version>1.1.2.6</version>
  </dependency>

  <dependency>
    <groupId>org.fusesource.leveldbjni</groupId>
    <artifactId>leveldbjni-all</artifactId>
    <version>1.8</version>   <!-- ARM64 미지원 아티팩트 -->
  </dependency>
</dependencies>
```

### 실행 ###
#### 1) 사용 가능한 변환 정의 확인 ####
```
atx custom def list
```
[결과]
```
Available transformation definitions:
  NAME                          VERSION   DESCRIPTION
  java-version-upgrade          1.x       Upgrade Java language/runtime version
  aws-sdk-java-v1-to-v2         1.x       Migrate AWS SDK for Java v1 -> v2
  x86-to-graviton-java          1.x       Migrate Java apps from x86 to AWS Graviton (ARM64)
  ...
```
#### 2) 변환 실행 (자율 모드) ####
```
atx custom def exec \
  -p . \
  -n x86-to-graviton-java \
  -c "mvn -q clean package" \
  -x                       # 비대화형(개입 없이 자율 실행)
```
이후 에이전트가 관리형 4단계를 진행합니다. 이 변환의 핵심 동작은 공식 스킬 설명 그대로 "아키텍처 비호환성 식별 → 네이티브 라이브러리의 ARM64 지원 검증 → ARM64를 막는 의존성만 업데이트 → ARM64에서 테스트"입니다 (Java x86-to-Graviton 스킬).

#### 단계 1 — 분석 (Analyze) ####

```
[Phase 1/4] Analyzing architecture compatibility...
  - Scanning dependency tree (mvn dependency:tree)
  - Checking native (JNI) artifacts for aarch64/arm64 support

  BLOCKERS FOUND (2):
  ✗ org.xerial.snappy:snappy-java:1.1.2.6
      reason: no aarch64 native binary bundled (added in >= 1.1.8.x)
  ✗ org.fusesource.leveldbjni:leveldbjni-all:1.8
      reason: artifact ships x86-only native libs; no maintained ARM64 build

  PURE-JAVA DEPS: no changes required (JVM bytecode is architecture-independent)
```

#### 단계 2 — 수정 (Fix) ####

```
[Phase 2/4] Applying minimal, targeted fixes...
  - snappy-java: 1.1.2.6 -> 1.1.10.5 (bundles aarch64)
  - leveldbjni-all(x86-only) -> replaced with ARM64-capable alternative
  - Recompiling for verification
```
* pom.xml 변경
```
   <dependency>
     <groupId>org.xerial.snappy</groupId>
     <artifactId>snappy-java</artifactId>
-    <version>1.1.2.6</version>
+    <version>1.1.10.5</version>
   </dependency>

-  <dependency>
-    <groupId>org.fusesource.leveldbjni</groupId>
-    <artifactId>leveldbjni-all</artifactId>
-    <version>1.8</version>
-  </dependency>
+  <dependency>
+    <groupId>org.openlabtesting.leveldbjni</groupId>
+    <artifactId>leveldbjni-all</artifactId>
+    <version>1.8</version>   <!-- includes linux/aarch64 native libs -->
+  </dependency>
```
포인트: 순수 Java 의존성이나 애플리케이션 비즈니스 로직은 건드리지 않습니다. ARM64를 막는 네이티브 의존성만 최소 변경합니다.

#### 단계 3 — 검증 (Validate) ####

```
[Phase 3/4] Validating on ARM64...
  $ mvn -q clean package        # 사용자가 -c 로 준 빌드 명령
  BUILD SUCCESS

  Running tests on aarch64 runtime (Amazon Corretto, ARM64)...
  Tests run: 143, Failures: 0, Errors: 0, Skipped: 0
  Native load check: snappy(aarch64) OK, leveldbjni(aarch64) OK
```

#### 단계 4 — 문서화 (Document) ####

```
[Phase 4/4] Writing transformation report...
  -> GRAVITON_MIGRATION_REPORT.md

Summary
  Blockers resolved : 2
  Dependencies changed : 2 (native only)
  App source changes : 0
  Build : SUCCESS on arm64
  Tests : 143 passed
  Ready for Graviton (e.g., c7g/m7g/r7g) deployment.
```
