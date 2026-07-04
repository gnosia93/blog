from sentence_transformers import SentenceTransformer, util

model = SentenceTransformer('BAAI/bge-m3')

sentences = [
    "AWS 그라비톤 CP는 메모리 대역폭이 동급 인텔 인스턴스에 비해 더 넓다",
    "인텔 제온 프로세서는 싱글 코어 클럭이 그라비톤에 비해 높다",
    "오늘 점심은 무엇을 먹을까?"
]

embeddings = model.encode(sentences)

similarity = util.cos_sim(embeddings[0], embeddings[1])
print(f"하드웨어 문장 간 유사도: {similarity.item():.4f}")


# 1. 모델 구조 출력
print(model)

# 2. 모델의 전체 세부 아키텍처 아웃풋 보기
print(model[0].auto_model)

# 3. 모델 내부의 실제 트랜스포머 레이어(Encoder) 개수 출력
print("트랜스포머 레이어 개수: ", len(model[0].auto_model.encoder.layer))
