## BAAI/bge-m3 모델의 인프라 벤치마크 ##
이 모델은 일반적인 BERT(768차원)와 달리 1024차원 고밀도 벡터를 사용하고 최대 8192 토큰까지 지원하므로, 컨텍스트가 길어질수록 메모리 대역폭 싸움이 치열해진다.
따라서 벤치마크를 설계할 때 `단순 질문(짧은 문장)`과 `RAG 문서(긴 문장)` 두 가지 케이스를 모두 검증해야 정확한 스코어가 나온다.
구체적인 벤치마크 환경 구성 및 파이썬 검증 코드는 다음과 같다.

### 1. 벤치마크 환경 통제 (Fair 시나리오) ###
두 인스턴스의 하드웨어가 완벽히 동등한 조건에서 일대일 대결을 하도록 통제해야 합니다.
*	인스턴스 스펙 맞추기:
  * c6i.xlarge (4 vCPU / 8 GiB RAM / Intel Xeon)
  * c7g.xlarge (4 vCPU / 8 GiB RAM / AWS Graviton 3)
*	OS 및 런타임:
  * Ubuntu 22.04 LTS 혹은 Amazon Linux 2023 (aarch64용과 x86_64용 최신 OS)
*	Python 3.10+ 환경 및 동일한 버전의 sentence-transformers 라이브러리 사용
* 임베딩 엔진 라이브러리:
  * CPU 연산 속도를 극대화하기 위해 오픈소스 추론 엔진인 ONNX Runtime 기법을 쓰거나, PyTorch 환경에서 최신 CPU 가속 라이브러리(ipex 등)가 켜졌는지 점검해야 하지만, 첫 테스트는 순수 PyTorch CPU 모드로 먼저 일대일 비교를 진행합니다.


### 2. SentenceTransformer 란 ? ###
**SentenceTransformer**는 텍스트(단어, 문장, 나아가 문단 전체)를 인공지능이 이해할 수 있는 고차원의 숫자 배열인 '임베딩 벡터(Embedding Vector)'로 변환해 주는 가장 대중적이고 강력한 오픈소스 파이썬 라이브러리입니다.
우리가 앞서 이야기했던 SBERT(Sentence-BERT)나 BAAI/bge-m3 같은 소형 임베딩 모델들을 파이썬 환경에서 단 몇 줄의 코드로 아주 쉽게 가져와 쓸 수 있도록 패키징해 둔 "임베딩 전용 툴킷"이라고 보시면 됩니다.

오리지널 BERT 모델은 원래 문장 생성이나 문장 간의 완벽한 유사도 비교를 위해 만들어진 구조가 아닙니다.
만약 오리지널 BERT를 가지고 문장 A와 문장 B가 얼마나 비슷한지 비교(Cross-Encoder 방식)하려면, 두 문장을 하나로 묶어서 모델에 매번 새로 통과시켜야 했습니다. 이 방식은 서비스에 저장된 문서가 1만 개만 되어도 유저가 질문할 때마다 1만 번의 무거운 딥러닝 연산을 해야 하므로 실시간 서비스가 불가능했습니다.
이를 해결하기 위해 등장한 개념이 **SBERT(Sentence-BERT)**이며, 이를 누구나 쉽게 쓰도록 오픈소스로 구현한 것이 바로 SentenceTransformer 라이브러리입니다.

SentenceTransformer는 문장이 입력되면 내부의 트랜스포머 모델(BERT, RoBERTa 등)을 거쳐 문장 전체의 의미를 응축한 **고정된 크기의 벡터(예: 768차원 또는 1024차원의 실수 배열)**를 딱 한 번만 계산해서 뱉어냅니다.
이렇게 문장의 의미가 숫자로 구워지면(Embedding), 컴퓨터는 복잡한 딥러닝 연산을 다시 할 필요가 없습니다. 그저 숫자들이 채워진 두 배열 사이의 각도를 재는 **'코사인 유사도(Cosine Similarity)'**라는 아주 단순한 고등학교 수준의 수학 공식만 가지고 두 문장이 얼마나 비슷한지 0.00001초 만에 계산해 낼 수 있게 됩니다.

#### 주요 기능 ####
SentenceTransformer 라이브러리는 단순히 벡터를 뽑는 것뿐만 아니라, 문장 기반 AI 서비스를 만드는 데 필요한 핵심 편의 기능을 다 가지고 있습니다.
* model.encode(): 문장을 넣으면 임베딩 벡터 배열로 바꿔주는 핵심 메서드입니다.
* 유사도 계산 (util.cos_sim): 두 문장 벡터 간의 코사인 유사도를 바로 계산해 주는 내장 함수를 제공합니다.
* 시맨틱 검색 (util.semantic_search): 수많은 문서 벡터 중 유저의 질문 벡터와 가장 유사한 문서 Top-K개를 광속으로 찾아내는 검색 알고리즘이 내장되어 있습니다.

#### [파이썬 코드 예시] ####
```python
from sentence_transformers import SentenceTransformer, util

# 1. HuggingFace에 등록된 원하는 임베딩 모델 이름만 적으면 자동으로 다운로드 & 로드
model = SentenceTransformer('BAAI/bge-m3')

# 2. 문장들을 임베딩 벡터(숫자 배열)로 변환 (Encode)
sentences = [
    "AWS 그라비톤 CPU는 메모리 대역폭이 넓다.",
    "인텔 제온 프로세서는 싱글 코어 클럭이 높다.",
    "오늘 점심에는 따뜻한 국밥을 먹어야겠다."
]
embeddings = model.encode(sentences)

# 3. 문장 간의 유사도 비교 (코사인 유사도)
# 1번 문장(그라비톤)과 2번 문장(인텔)은 하드웨어 이야기라 유사도가 높게 나오고, 
# 3번 문장(국밥)은 완전히 다른 이야기라 유사도가 낮게 나옵니다.
similarity = util.cos_sim(embeddings[0], embeddings[1])
print(f"하드웨어 문장 간 유사도: {similarity.item():.4f}")**
```

#### ① SentenceTransformer (도구 / 라이브러리) ####
*	정체: 파이썬 개발자들이 임베딩 작업을 쉽게 할 수 있도록 페이스북/허깅페이스 진영의 엔지니어들이 만들어 놓은 **'소프트웨어 도구(라이브러리)'**입니다.
*	하는 일: 인공지능 모델 파일을 컴퓨터 메모리에 로드하고, 유저가 문장을 입력하면 토큰으로 쪼개서 모델에 밀어 넣어주고, 최종적으로 숫자 배열(벡터)로 변환해서 출력해 주는 모든 파이프라인(엔진 역할)을 총괄합니다.

#### ② BAAI/bge-m3 (뇌 / 모델 파일) ####
*	정체: 중국의 인공지능 연구소인 BAAI(베이징 인공지능연구원)에서 수천만 개의 문장을 가지고 막대한 전기세와 GPU를 써서 학습시켜 놓은 **'진짜 AI 뇌(모델 가중치 파일)'**입니다.
* 하는 일: "이 문맥과 저 문맥은 어떤 의미적 연관성이 있는가?"에 대한 실제 수학적 가중치(Weights) 값들을 1024차원의 거대한 행렬 데이터로 가지고 있습니다.

#### 트랜스포머 레이어 출력하기 (몇 계층인지 확인) ####
```
from sentence_transformers import SentenceTransformer

# 1. 궁금한 모델 로드
model = SentenceTransformer('BAAI/bge-m3')

# 2. 모델 구조 출력!
print(model)
```
출력 결과 창에 찍히는 내용 (bge-m3 기준 파싱):
```
SentenceTransformer(
  (0): Transformer({'max_seq_length': 8192, 'do_lower_case': False}) with Transformer model: XLMRobertaModel 
  (1): Pooling({'word_embedding_dimension': 1024, ...})
)
```
여기서 핵심 알맹이인 XLMRobertaModel을 더 깊게 뜯어보거나, Hugging Face 공식 도큐먼트의 config.json 파일을 열어보면 이 모델의 진짜 층수가 나옵니다.

#### 2. 우리가 비교하려는 모델들의 실제 층수 (스펙 비교) ####
실제 실무에서 많이 쓰는 모델들의 트랜스포머 층수를 비교해 보면 확연한 체급 차이가 보입니다.
*	jhgan/ko-sroberta-multitask (경량): 12층 (기본 BERT-base 아키텍처)
*	BAAI/bge-m3 (중형/우리가 쓸 것): 24층 (XLMRoberta-large 기반 아키텍처)
*	Qwen/Qwen3-Embedding-8B (대형): 32층 (Llama 계열의 대형 LLM 기반 아키텍처)



### 3. 실전 벤치마크 스크립트 (Python) ###
두 서버에 각각 아래 코드를 올린 뒤 실행하여 **"초당 몇 개의 문장을 처리하는지(Throughput)"**와 **"문장 1개당 몇 ms가 걸리는지(Latency)"**를 측정합니다.
```
import time
import numpy as np
from sentence_transformers import SentenceTransformer

# 1. BGE-M3 모델 로드 (CPU 명시)
print("Loading BAAI/bge-m3 model on CPU...")
model = SentenceTransformer('BAAI/bge-m3', device='cpu')

# 2. 더미 데이터 세팅 (실전 시나리오 반영)
# 시나리오 A: 유저가 던지는 짧은 검색 쿼리 (평균 15단어)
short_texts = ["최신 AWS 그라비톤 프로세서의 L3 캐시 메모리 아키텍처와 대역폭 효율성 조사"] * 100

# 시나리오 B: RAG 엔진에 들어갈 긴 컨텍스트 문서 조각 (평균 300단어)
long_text_chunk = """
AWS Graviton3 프로세서는 클라우드 워크로드를 위해 Amazon에서 맞춤 설계한 64비트 ARM 기반 칩셋입니다. 
기존 2세대 그라비톤에 비해 뛰어난 컴퓨터 연산 성능과 2배 더 넓은 DDR5 메모리 대역폭을 제공합니다. 
특히 대규모 트랜스포머 기반 임베딩 연산 시, 수많은 물리 코어가 격자 구조(Mesh Network)로 연결되어 
L3 캐시 풀에 균일하고 빠르게 접근할 수 있어 인덱싱 작업의 병목을 크게 해소합니다. 
하이퍼스레딩 없이 독립된 물리 코어 성능을 보장하므로 자바 가상 머신(JVM)의 가비지 컬렉션(GC) 성능 및 
문장 임베딩 벡터 생성 시 일관된 꼬리 지연 시간(Tail Latency) 보장에 압도적인 효율을 자랑합니다.
"""
long_texts = [long_text_chunk] * 50  # 연산량이 크므로 50개만 진행

def run_benchmark(name, text_list, batch_size=1):
    print(f"\n=== {name} 벤치마크 시작 (Batch Size: {batch_size}) ===")
    
    # 워밍업 (Warming up: 초기에 캐시나 라이브러리 로드 시간 제외 목적)
    model.encode(text_list[:2], batch_size=batch_size, normalize_embeddings=True)
    
    # 본 측정
    start_time = time.perf_counter()
    embeddings = model.encode(text_list, batch_size=batch_size, normalize_embeddings=True)
    end_time = time.perf_counter()
    
    total_time = end_time - start_time
    avg_latency = (total_time / len(text_list)) * 1000 # ms 단위
    throughput = len(text_list) / total_time
    
    print(f"총 소요 시간: {total_time:.4f} 초")
    print(f"문장 1개당 평균 지연 시간(Latency): {avg_latency:.2f} ms")
    print(f"초당 처리 문장 수(Throughput): {throughput:.2f} sentences/sec")
    return avg_latency, throughput

# 실행 (배치 크기를 1과 8로 각각 테스트하여 하드웨어 효율 측정)
run_benchmark("짧은 문장 쿼리 (Batch 1)", short_texts, batch_size=1)
run_benchmark("짧은 문장 쿼리 (Batch 8)", short_texts, batch_size=8)
run_benchmark("긴 문서 청크 (Batch 1)", long_texts, batch_size=1)
run_benchmark("긴 문서 청크 (Batch 8)", long_texts, batch_size=8)
```

### 4. 결과 분석 및 '가성비(Price-Performance)' ###
실험이 끝나면 단순히 속도만 보면 안 되고, **"1달러당 누가 더 많은 벡터를 구워냈는가"**를 계산해야 완벽한 기술 블로그 소스가 완성됩니다.
각 서버의 출력창에 나온 Throughput (초당 처리량) 수치를 기반으로 아래 계산식을 대입합니다.
‭$$\text{달러당 처리량} = \frac{\text{초당 처리 문장 수 (Throughput)} \times 3600}{\text{인스턴스 시간당 비용 (On-Demand Cost)}}$$‬‭‬

#### 📊 예상되는 결과 포인트 (관전 포인트) ####

1.	`짧은 문장 (Batch 1)`: 인텔 제온의 '싱글 코어 높은 깡클럭' 덕분에 c6i가 아주 미세하게 레이턴시가 앞서거나 비등할 수 있습니다.
2.	`긴 문서 청크 + Batch 8`: BAAI/bge-m3가 1024차원의 행렬과 토큰을 쏟아내며 메모리를 풀로 당기기 시작하면, DDR5 대역폭과 물리 코어를 독점하는 그라비톤3(c7g)이 초당 처리량(Throughput)에서 인텔을 추월하기 시작합니다.
3.	`가성비(Price-Performance)`: c7g 인스턴스가 인텔에 비해 기본 단가 자체가 약 15~17% 저렴하기 때문에, 달러당 처리량(성능비) 측면에서는 그라비톤이 최종 판정승을 거둘 확률이 매우 높습니다.
두 인스턴스에 위 스크립트를 돌려 나온 로그 스크린샷과 가성비 변환 테이블을 나란히 배치하면, 사내 보고서나 기술 블로그에서 최고의 설득력을 갖춘 데이터가 될 것입니다!
