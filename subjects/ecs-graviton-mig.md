* 워커노드 그라비톤 전환
* 파ㄱ이트 그라비톤 전환


Amazon ECS, 이제 AWS Fargate를 통해 AWS Graviton 기반 Spot 컴퓨팅 지원
게시된 날짜: 2024년 9월 6일
Amazon Elastic Container Service(Amazon ECS)는 이제 AWS Fargate Spot을 통해 AWS Graviton 기반 컴퓨팅을 지원합니다. 이 기능을 사용하면 Fargate 요금 대비 최대 70% 할인된 가격으로 내결함성이 있는 ARM 기반 애플리케이션을 실행할 수 있습니다. AWS Graviton 프로세서는 AWS로 맞춤 제작되어 클라우드 워크로드에 최고의 가격 대비 성능을 제공합니다.

AWS Fargate를 통해 Amazon ECS를 사용하면 고객이 서버리스 방식으로 대규모로 워크로드를 배포하고 구축할 수 있습니다. 고객은 ARM 기반 워크로드를 실행하여 가격 대비 성능을 높일 수 있습니다. 오늘부터 고객은 AWS Fargate Spot에서 내결함성 ARM 기반 워크로드를 실행하여 비용을 더욱 최적화할 수 있습니다. 시작하려면, 현재 하는 것처럼 cpu-architecture = ARM64로 작업 정의를 구성하고 Amazon ECS 서비스 또는 독립형 작업을 실행할 용량 공급자로 FARGATE_SPOT을 선택하면 됩니다. Amazon ECS는 AWS 클라우드에서 사용 가능한 예비 AWS Graviton 기반 컴퓨팅 용량을 서비스 또는 작업 실행에 활용합니다. 이제 Graviton 기반 컴퓨팅을 통해 Spot 용량의 친숙한 비용 최적화 수단을 사용하여 서버리스 컴퓨팅의 간편성을 얻을 수 있습니다.
