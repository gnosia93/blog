Spring Boot + Gradle 버전입니다. 여전히 파일시스템 접근이 차단되어 제가 직접 생성은 못 하므로, 복사해서 쓰실 수 있는 완전한 파일 일체를 드립니다. ARM64 blocker 2개(snappy-java 구버전, leveldbjni-all:1.8)를 그대로 포함했고, 실행 가능한 REST 엔드포인트로 만들었습니다.

디렉터리 구조

graviton-demo/
├── settings.gradle
├── build.gradle
└── src
    ├── main
    │   ├── java/com/example/demo/DemoApplication.java
    │   ├── java/com/example/demo/CompressionService.java
    │   ├── java/com/example/demo/CompressionController.java
    │   └── resources/application.properties
    └── test/java/com/example/demo/CompressionServiceTest.java
1. settings.gradle
groovy

rootProject.name = 'graviton-demo'
2. build.gradle
groovy

plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.5'
    id 'io.spring.dependency-management' version '1.1.4'
}

group = 'com.example'
version = '1.0.0'

java {
    sourceCompatibility = '17'
}

repositories {
    mavenCentral()
}

// BLOCKER #1: snappy-java 는 Spring Boot BOM 이 버전을 관리하므로,
// ARM64(aarch64) 미지원 구버전을 강제로 고정해 실제 blocker 를 재현한다.
// (Spring Boot dependencies 가 인식하는 버전 프로퍼티를 덮어쓴다)
ext['snappy-java.version'] = '1.1.2.6'

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'

    // 버전은 위 ext 프로퍼티(1.1.2.6)로 강제됨 -> Graviton 에서 네이티브 로드 실패
    implementation 'org.xerial.snappy:snappy-java'

    // BLOCKER #2: leveldbjni-all:1.8 은 x86 전용 네이티브만 포함(ARM64 없음).
    // ARM64 해결책: org.openlabtesting.leveldbjni:leveldbjni-all:1.8 로 교체
    implementation 'org.fusesource.leveldbjni:leveldbjni-all:1.8'

    testImplementation 'org.springframework.boot:spring-boot-starter-test'
}

tasks.named('test') {
    useJUnitPlatform()
}
3. src/main/java/com/example/demo/DemoApplication.java
java

package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
4. src/main/java/com/example/demo/CompressionService.java
java

package com.example.demo;

import org.springframework.stereotype.Service;
import org.xerial.snappy.Snappy;

import java.nio.charset.StandardCharsets;

@Service
public class CompressionService {

    /** Snappy 압축/해제 왕복. 구버전 snappy 는 ARM64 에서 네이티브 로드에 실패한다. */
    public String roundTrip(String input) throws Exception {
        byte[] compressed = Snappy.compress(input.getBytes(StandardCharsets.UTF_8));
        byte[] restored = Snappy.uncompress(compressed);
        return new String(restored, StandardCharsets.UTF_8);
    }

    public String nativeVersion() {
        return Snappy.getNativeLibraryVersion();
    }
}
5. src/main/java/com/example/demo/CompressionController.java
java

package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class CompressionController {

    private final CompressionService service;

    public CompressionController(CompressionService service) {
        this.service = service;
    }

    @GetMapping("/compress")
    public Map<String, Object> compress(
            @RequestParam(defaultValue = "Hello from x86 - migrating to AWS Graviton!") String text)
            throws Exception {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("snappyNativeVersion", service.nativeVersion());
        result.put("input", text);
        result.put("roundTrip", service.roundTrip(text));
        return result;
    }
}
6. src/main/resources/application.properties
properties

server.port=8080
7. src/test/java/com/example/demo/CompressionServiceTest.java
java

package com.example.demo;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CompressionServiceTest {

    private final CompressionService service = new CompressionService();

    @Test
    void snappyRoundTripWorks() throws Exception {
        String input = "AWS Graviton price-performance test payload";
        assertEquals(input, service.roundTrip(input));
    }
}
생성 + Gradle Wrapper + Git 초기화
파일을 만든 뒤, Gradle wrapper를 생성합니다(로컬에 gradle이 설치돼 있어야 함). ATX는 유효한 Git 레포가 필요합니다.

bash

cd graviton-demo

# Gradle Wrapper 생성 (gradlew 스크립트/jar 은 텍스트로 못 드려서 이 방식으로 생성)
gradle wrapper --gradle-version 8.7

git init && git add . && git commit -m "Initial commit (Spring Boot, x86, ARM64 blockers)"
gradle이 없으면 SDKMAN(sdk install gradle)이나 Homebrew(brew install gradle)로 설치하세요. 설치된 gradle이 있으면 아래 명령들의 ./gradlew를 gradle로 대체해도 됩니다.

마이그레이션 전 상태 확인
bash

./gradlew clean build
# - Intel(x86) Mac  : BUILD SUCCESSFUL, 테스트 통과 (Graviton 배포 때만 문제)
# - Apple Silicon    : 구버전 snappy 가 aarch64 네이티브 로드 실패 -> 테스트 실패로 blocker 재현

# 앱 실행 후 엔드포인트 확인
./gradlew bootRun
# 다른 터미널에서:
curl "http://localhost:8080/compress?text=graviton"
네이티브 blocker 확인:

bash

./gradlew dependencies --configuration runtimeClasspath | grep -E "snappy|leveldbjni"
ATX로 변환 실행
bash

atx custom def list
atx custom def exec -p . -n x86-to-graviton-java -c "./gradlew clean build" -x
기대 결과 (마이그레이션 후)
ext['snappy-java.version']가 aarch64 포함 버전(예: 1.1.10.x)으로 상향
leveldbjni-all → ARM64 지원 아티팩트로 교체 (예: org.openlabtesting.leveldbjni:leveldbjni-all:1.8)
애플리케이션 소스는 변경 없음 — 네이티브 차단 의존성만 최소 수정
ARM64에서 ./gradlew clean build 성공 및 테스트 통과
Kotlin DSL(build.gradle.kts)로 원하시거나, 멀티모듈 구성, 또는 Docker(멀티아키 buildx) 배포까지 이어지는 버전이 필요하면 말씀해 주세요. 그리고 폴더를 열어주시면 다음엔 제가 직접 파일 생성까지 처리해 드릴 수 있습니다.

참고: CLI 구문과 4단계 동작은 AWS 공식 문서 기준이며, 버전 번호 등 일부 수치는 전형적 사례 기준 예시입니다.
