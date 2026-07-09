"Kiro power for AWS Transform" + "AWS Transform agent skill" + "AWS Transform IDE plugin" — 세 가지를 각각 구분해서요 (DevOps 블로그).

#### Kiro Skill (Agent Skill) — 앞에서 본 SKILL.md ####
* SKILL.md 폴더 형태의 오픈 표준 전문 지식/절차
* 위치: ~/.kiro/skills/ (사용자) 또는 .kiro/skills/ (워크스페이스)
* 성격: "어떻게 하는지"를 담은 지침. 에이전트가 필요할 때만 로드(progressive disclosure)
* 이식성: Claude Code, Codex 등 다른 도구에서도 동일하게 동작

#### Kiro Power — Kiro 고유의 "패키지/통합 단위" ####
* 성격: 문서 + 워크플로 가이드(steering 파일) + 선택적으로 MCP 서버까지 묶은 패키지
* 핵심 차이: 단순 지침을 넘어 실제 도구 연동(MCP 서버) 을 포함할 수 있음. Power가 MCP 서버를 품고 있으면, 그 도구들은 Power 인터페이스를 통해 호출됩니다
즉 "지식(스킬)"보다 범위가 넓은 설치·통합 단위. 에디터 안에서 설계·실행이 매끄럽게 되도록 묶어주는 역할
