## Java/JVM 벤치마크 스위트 옵션 ##

###  1. SPECjbb2015 — JVM 서버 벤치의 사실상 표준
- 업계 표준. "max-jOPS(처리량)"과 "critical-jOPS(SLA 지연 하 처리량)" 두 지표를 냄 → 처리량 + 지연을 한 번에
- Graviton 관련 벤치마크 글에서 가장 많이 인용되는 게 이것
- 단점: 상용 라이선스(유료). 개인 블로그면 진입장벽

### 2. Renaissance Suite — 무료, 현대적 JVM 벤치마크
- Apache 2.0 라이선스, JAR 하나로 실행. Spark, Netty, 동시성, JIT 등 다양한 워크로드
- 학술·엔지니어 신뢰도 높고 재현 쉬움. 블로그용으로 가장 추천

### 3. DaCapo Benchmark — 무료, 오래된 표준
- 실제 앱 기반(Tomcat, Lucene, H2 등). 최신 23.11-chopin 릴리스가 aarch64 잘 지원
- Renaissance와 함께 쓰면 커버리지 넓어짐

### 4. TechEmpower Framework Benchmarks — 웹 프레임워크 처리량 표준
- 우리가 짠 것과 가장 성격이 유사(REST + DB). Spring 포함 수백 프레임워크 시나리오(JSON/DB query/updates/plaintext)가 이미 구현돼 있음
- "Spring Boot REST API" 시나리오를 직접 안 짜고 그대로 쓸 수 있음 ← 지금 니즈에 딱

### 5. JMH — 마이크로벤치 (앞서 워크로드 A에서 언급)
- 스위트라기보단 하네스. 특정 메서드 수준 측정용

## 목적별 추천 ##
```
  ┌─────────────────────────────────────────┬──────────────────────────────────────────────┐
  │                원하는 것                │                     추천                     │
  ├─────────────────────────────────────────┼──────────────────────────────────────────────┤
  │ Spring REST + DB 처리량을 표준 스위트로 │ TechEmpower (Spring 시나리오 그대로)         │
  ├─────────────────────────────────────────┼──────────────────────────────────────────────┤
  │ JVM 전반 성능/GC를 무료로 신뢰성 있게   │ Renaissance + DaCapo                         │
  ├─────────────────────────────────────────┼──────────────────────────────────────────────┤
  │ 업계 표준 서버 지표(유료 감수)          │ SPECjbb2015                                  │
  ├─────────────────────────────────────────┼──────────────────────────────────────────────┤
  │ 종합 블로그                             │ TechEmpower(웹) + Renaissance(JVM 코어) 조합 │
  └─────────────────────────────────────────┴──────────────────────────────────────────────┘
```

## 추천 ##
Spring Boot REST가 주제니까 TechEmpower의 Spring 시나리오를 실측 대상으로 쓰고, "순수 JVM/GC 격차"는 Renaissance로 보강하는 조합입니다. 
TechEmpower는 자체 하네스(tfb 툴킷, Docker 기반 실행/결과수집)가 있다.

- TechEmpower 중심 (Spring 시나리오 실행 + Graviton/x86 결과 뽑기)
- Renaissance/DaCapo 중심 (무료 JVM 스위트 실행)

## 33 ##
셋업 & 실행

git clone https://github.com/TechEmpower/FrameworkBenchmarks
cd FrameworkBenchmarks

# 1) 먼저 검증 모드 — 앱이 뜨고 응답이 규격에 맞는지 확인 (부하 X, 빠름)
./tfb --mode verify --test spring

# 2) 실제 벤치마크 — 부하 생성 + 결과 수집
./tfb --mode benchmark --test spring spring-data-jdbc spring-jooq

# 특정 타입만
./tfb --mode benchmark --test spring --type json db queries

- 결과는 results/ 아래 타임스탬프 폴더에 JSON으로 떨어지고, results.json을 tfb 결과 시각화 페이지나 자체 도구로 볼 수 있습니다.

Graviton vs x86 비교 방법 (여기가 핵심)

TechEmpower 하네스는 앱·DB·부하생성기를 같은 호스트에서 돌리는 게 기본입니다. 아키텍처 비교는 이렇게:

1. 동일 인스턴스 계열, 아키만 다르게 EC2를 띄웁니다 (예: m7i = Intel, m7a = AMD, m8g/m9g = Graviton), vCPU 수 통일.
2. 각 인스턴스에서 동일 커맨드로 ./tfb --mode benchmark --test spring ... 실행.
  - tfb가 Java 이미지를 각 호스트 아키에 맞게 로컬 빌드하므로 멀티아치 이미지를 따로 관리할 필요가 없습니다 (아까 우리가 신경 쓴 QEMU 함정을 하네스가 회피).
3. 각 호스트의 results/.../results.json을 모아서 아키별로 비교.

함정 (블로그 신뢰도 직결)

- 단일 호스트 co-location: 기본 구성은 앱+DB+wrk가 한 머신. 그래서 "순수 서버 성능"이 아니라 "이 인스턴스에서 전체 스택 처리량"을 재는 겁니다. 순수 서버 성능을 원하면 tfb의 분리 실행(--network + TFB_* 환경변수로 database/client 호스트 분리) 구성을 써야 하는데, 셋업이 늘어납니다. 블로그엔 "동일 스택 co-located 비교"임을 명시하면 충분합니다.
- vCPU 정의 차이: x86 vCPU=SMT 스레드, Graviton vCPU=물리 코어. 앞서 말한 그 포인트, 반드시 표기.
- 빌드 확인: 각 호스트에서 앱이 native 아키로 빌드됐는지 (docker inspect).
- wrk 워밍업: tfb가 warmup 구간을 두지만, JIT 안정화 위해 반복 실행 후 중앙값 사용 권장.


결정할 것

두 가지만 정하면 돼요:

- 변형 범위: spring(JdbcTemplate) 하나만 깔끔하게 vs spring+data-jdbc+jooq 비교(ORM별 아키 영향까지 보면 글이 풍부해짐). Mongo는 DB가 달라져 아키 비교엔 변수만 늘어서 제외 추천.
- 구성: 기본 co-located(간단, 추천) vs 앱/DB/클라이언트 분리(정밀하지만 셋업 큼).

