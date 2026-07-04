import time
import numpy as np
from sentence_transformers import SentenceTransformer

print("Loading BAAI/bge-m3 model on CPU...")
model = SentenceTransformer('BAAI/bge-m3', device='cpu')

short_texts = ["최신 AWS 그라비톤 프로세서의 L3 캐시 메모리 아키텍처와 대역폭에 대한 고찰"] * 100 

long_text_chunk = """AWS Graviton3 프로세서는 클라우드 워크로드를 위해 Amazon에서 맞춤 설계한 
64비트 ARM 기반 칩셋입니다. 
기존 2세대 그라비톤에 비해 뛰어난 컴퓨터 연산 성능과 2배 더 넓은 DDR5 메모리 대역폭을 제공합니다. 
특히 대규모 트랜스포머 기반 임베딩 연산 시, 수많은 물리 코어가 격자 구조(Mesh Network)로 연결되어 
L3 캐시 풀에 균일하고 빠르게 접근할 수 있어 인덱싱 작업의 병목을 크게 해소합니다. 
하이퍼스레딩 없이 독립된 물리 코어 성능을 보장하므로 자바 가상 머신(JVM)의 가비지 컬렉션(GC) 성능 및 
문장 임베딩 벡터 생성 시 일관된 꼬리 지연 시간(Tail Latency) 보장에 압도적인 효율을 자랑합니다."""

long_texts = [long_text_chunk] * 50  # 연산량이 크므로 50개만 진행

def run_benchmark(name, texts, batch_size=1):
    print(f"\n=== {name} 벤치마크 시작 ===")

    # Warm-up
    model.encode(texts[:2], batch_size=batch_size, normalize_embeddings=True)

    # Benchmark
    start_time = time.perf_counter()
    embeddings = model.encode(texts, batch_size=batch_size, normalize_embeddings=True)
    end_time = time.perf_counter()
    
    total_time = end_time - start_time
    avg_latency = total_time / len(texts) * 1000 # milliseconds
    throughput = len(texts) / total_time

    print(f"총 소요 시간: {total_time:.4f} 초")
    print(f"문장 1개당 평균 지연 시간: {avg_latency:.4f} ms")
    print(f"처리 속도: {throughput:.2f} 문장/초")

    return avg_latency, throughput

# Run benchmarks
run_benchmark("짧은 문장 쿼리 (Batch 1)", short_texts, batch_size=1)
run_benchmark("짧은 문장 쿼리 (Batch 8)", short_texts, batch_size=8)
run_benchmark("긴 문서 청크 (Batch 1)", long_texts, batch_size=1)
run_benchmark("긴 문서 청크 (Batch 8)", long_texts, batch_size=8)