
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

