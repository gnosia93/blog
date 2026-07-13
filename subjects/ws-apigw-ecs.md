유저 정보를 매핑할 **DB(여기서는 가볍게 DynamoDB)**가 필요하며, 브라우저와 API Gateway, 그리고 백엔드(ECS 대용 Mock)가 어떻게 맞물리는지 전체 코드이다.

### 1. 🗄️ DB 설계 (DynamoDB 테이블)
먼저 웹소켓 연결 관리를 위해 DynamoDB 테이블을 하나 생성해야 합니다.
•	테이블 이름: websocket_connections
•	파티션 키 (PK): connectionId (String)

### 2. 🌐 AWS API Gateway 설정 (핵심 구조)
AWS 콘솔에서 API Gateway ➡️ WebSocket API를 생성할 때, 핵심 라우트(Route) 3개를 다음과 같이 설정하고 람다(Lambda) 함수와 연결합니다.
	1.	$connect 라우트: 브라우저가 처음 들어올 때 실행 (DynamoDB에 ID 저장)
	2.	$disconnect 라우트: 브라우저 창을 닫을 때 실행 (DynamoDB에서 ID 삭제)
	3.	ping 라우트: 타임아웃을 막기 위한 핑퐁용 (단순 응답)

🛠️ $connect 라우트 람다 소스코드 (Python)
```
import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('websocket_connections')

def lambda_handler(event, context):
    # API Gateway가 자동으로 넘겨준 고유 소켓 ID와 쿼리스트링으로 받은 유저 ID
    connection_id = event['requestContext']['connectionId']
    user_id = event.get('queryStringParameters', {}).get('userId', 'anonymous')
    
    # DB에 매핑 정보 저장
    table.put_item(Item={
        'connectionId': connection_id,
        'userId': user_id
    })
    
    return {'statusCode': 200, 'body': 'Connected'}
```

### 3. 💻 웹 브라우저 (Frontend - HTML/JS)
10분 타임아웃을 막기 위한 핑퐁(Heartbeat) 로직이 포함된 순수 자바스크립트 웹 브라우저 코드입니다.
```
<!DOCTYPE html>
<html lang="ko">
<head><title>WebSocket Client</title></head>
<body>
    <h2>AI 에이전트 알림 대기방</h2>
    <div id="messages"></div>

    <script>
        // 1. API Gateway 웹소켓 주소로 연결 (유저 ID를 쿼리스트링으로 전달)
        const userId = "user_charlie_123";
        const socket = new WebSocket(`wss://your-api-id.execute-api.ap-northeast-2.amazonaws.com/production?userId=${userId}`);
        const messageDiv = document.getElementById("messages");

        // 연결 성공 시
        socket.onopen = () => {
            messageDiv.innerHTML += "<p>[시스템] 웹소켓 연결 성공! 알림을 대기합니다...</p>";
            
            // 🔥 [중요] 10분 타임아웃 방지: 3분(180000ms)마다 빈 메시지(Ping) 발송
            setInterval(() => {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({ action: "ping" }));
                    console.log("Ping 보냄 (타임아웃 방지)");
                }
            }, 180000); 
        };

        // 서버(API Gateway)로부터 실시간 알림을 받았을 때
        socket.onmessage = (event) => {
            const data = json.parse(event.data);
            messageDiv.innerHTML += `<p style="color: blue;">[알림] ${data.result}</p>`;
        };

        socket.onclose = () => { messageDiv.innerHTML += "<p>[시스템] 연결이 종료되었습니다.</p>"; };
    </script>
</body>
</html>
```

### 4. 🚀 백엔드 가상 워커 (ECS Mock URL 역역할 코드)
AI 에이전트 작업이 완전히 끝나서, 웹소켓 연결과 무관한 외부 프로세스가 API Gateway에게 "얘한테 알림 쏴줘!"라고 때리는 파이썬 코드입니다.
```
import boto3
import json

# 1. AWS API Gateway 웹소켓 전용 클라이언트 생성 (웹 환경의 콜백 URL 지정)
# stage 이름(예: production)까지 주소 끝에 꼭 붙여야 합니다.
apigw_client = boto3.client(
    'apigatewaymanagementapi',
    endpoint_url='https://your-api-id.execute-api.ap-northeast-2.amazonaws.com/production'
)

def mock_ecs_task_finished():
    print("ECS 워커: 랭그래프 에이전트가 5분간의 데이터 분석을 마쳤습니다.")
    
    # 원래는 DB에서 user_id로 connectionId를 조회해와야 합니다.
    # 여기서는 예시로 하드코딩합니다.
    target_connection_id = "A1b2C3d4_mock_id" 
    
    # 2. API Gateway에게 역으로 Push 요청 전송!
    try:
        apigw_client.post_to_connection(
            ConnectionId=target_connection_id,
            Data=json.dumps({
                "status": "SUCCESS",
                "result": "🎉 요청하신 랭그래프 복잡한 보고서 작성이 완료되었습니다! 다운로드 하세요."
            })
        )
        print("API Gateway에게 알림 배달대행 요청 완료!")
    except apigw_client.exceptions.GoneException:
        print("오류: 사용자가 이미 브라우저 창을 닫아서 연결이 끊어졌습니다.")

# 가상 실행
mock_ecs_task_finished()
```
🧐 흐름 정리
브라우저가 wss://로 접속하면 람다가 DynamoDB에 소켓 주소(connectionId)를 적어두고, 3분마다 브라우저가 Ping을 날려 타임아웃을 방어합니다. 이후 무거운 작업을 끝낸 ECS Mock 코드가 boto3 라이브러리로 API Gateway의 문을 두드려 유저에게 알림을 성공적으로 배달하게 됩니다!
