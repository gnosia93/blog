
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

* 사람이 일일이 dependency:tree를 뒤져 ARM64 미지원 네이티브 라이브러리를 찾아내던 작업을 에이전트가 자동으로 식별
* 순수 Java는 그대로 두고 차단 의존성만 교체 → 변경 최소화, 리스크 감소
* 실제 ARM64에서 빌드/테스트까지 검증한 뒤 리포트 생성 → "며칠 단위" 전환의 실체

## 실제 데모 ##
확인 결과 이 세션에는 열린 작업 폴더가 없고 파일시스템 접근이 차단되어 있어, 제가 직접 파일을 생성할 수는 없습니다. 그래서 그대로 복사하면 바로 빌드/실행되는 완전한 프로젝트 일체를 아래에 드리겠습니다. 파일 3개만 만들면 됩니다.

이 프로젝트는 의도적으로 ARM64 blocker 2개를 넣었습니다.

* snappy-java:1.1.2.6 — 이 구버전은 aarch64 네이티브 바이너리가 없어 Graviton에서 로드 실패 (코드에서 실제로 사용 → 실행 시 검증됨)
* leveldbjni-all:1.8 — x86 전용 네이티브만 포함(ARM64 없음). 의존성 분석기가 잡아내는 대표 사례

#### 디렉터리 구조 ####
```
graviton-demo/
├── pom.xml
└── src
    ├── main/java/com/example/App.java
    └── test/java/com/example/AppTest.java
```
* pom.xml
```
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.example</groupId>
  <artifactId>graviton-demo</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>

  <properties>
    <maven.compiler.source>1.8</maven.compiler.source>
    <maven.compiler.target>1.8</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <!-- BLOCKER #1: 구버전 snappy-java 는 aarch64(ARM64) 네이티브 바이너리가 없음.
         AWS Graviton 에서 native lib 로드 실패. 해결: >= 1.1.8.x 로 업그레이드 -->
    <dependency>
      <groupId>org.xerial.snappy</groupId>
      <artifactId>snappy-java</artifactId>
      <version>1.1.2.6</version>
    </dependency>

    <!-- BLOCKER #2: leveldbjni-all:1.8 은 x86 전용 네이티브만 포함(ARM64 없음).
         분석기가 잡아내는 대표적 네이티브 의존성.
         ARM64 해결책: org.openlabtesting.leveldbjni:leveldbjni-all:1.8 로 교체 -->
    <dependency>
      <groupId>org.fusesource.leveldbjni</groupId>
      <artifactId>leveldbjni-all</artifactId>
      <version>1.8</version>
    </dependency>

    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.1.0</version>
        <configuration>
          <mainClass>com.example.App</mainClass>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```
* App.java
```
package com.example;

import org.xerial.snappy.Snappy;
import java.nio.charset.StandardCharsets;

public class App {

    /** Snappy 압축/해제 왕복. 구버전 snappy 는 ARM64 에서 네이티브 로드에 실패한다. */
    public static String roundTrip(String input) throws Exception {
        byte[] compressed = Snappy.compress(input.getBytes(StandardCharsets.UTF_8));
        byte[] restored = Snappy.uncompress(compressed);
        return new String(restored, StandardCharsets.UTF_8);
    }

    public static void main(String[] args) throws Exception {
        String message = "Hello from x86 - migrating to AWS Graviton!";
        String result = roundTrip(message);

        System.out.println("Snappy native version : " + Snappy.getNativeLibraryVersion());
        System.out.println("Original              : " + message);
        System.out.println("Round-tripped         : " + result);
        System.out.println("Match                 : " + message.equals(result));
    }
}
```
* AppTest.java
```
package com.example;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class AppTest {

    @Test
    public void snappyRoundTripWorks() throws Exception {
        String input = "AWS Graviton price-performance test payload";
        assertEquals(input, App.roundTrip(input));
    }
}
```

### 프로젝트 생성 + Git 초기화 (ATX는 유효한 Git 레포 필요) ###
* 사전준비 
```
cd graviton-demo
git init && git add . && git commit -m "Initial commit (x86, ARM64 blockers)"

mkdir -p graviton-demo/src/main/java/com/example graviton-demo/src/test/java/com/example
# 그다음 각 위치에 위 파일 내용 붙여넣기
```
* 마이그레이션 전 상태 확인
```
mvn clean package
# - Intel(x86) Mac 이면: BUILD SUCCESS, 테스트 통과 (Graviton 배포 시에만 문제)
# - Apple Silicon(arm64) Mac 이면: 구버전 snappy 가 네이티브 로드 실패 -> 테스트 실패
#   (로컬에서 바로 ARM64 blocker 를 재현하게 됩니다)
```
* 네이티브 blocker를 눈으로 확인하려면:
```
mvn dependency:tree | grep -E "snappy|leveldbjni"
```
* ATX로 변환 실행
```
atx custom def list
atx custom def exec -p . -n x86-to-graviton-java -c "mvn -q clean package" -x
```
* snappy-java → 1.1.10.x (aarch64 포함)로 버전 업
* leveldbjni-all → ARM64 지원 아티팩트로 교체 (예: org.openlabtesting.leveldbjni:leveldbjni-all:1.8)
* 애플리케이션 소스(App.java)는 변경 없음 — 네이티브 차단 의존성만 최소 수정
* ARM64에서 mvn clean package 성공 및 테스트 통과




