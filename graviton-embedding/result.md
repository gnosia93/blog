## bf16 성능 테스트 ##

* C8i.2xlarge
```
lscpu | grep amx

```

* C9g.2xlarge
```
$ DNNL_DEFAULT_FPMATH_MODE=BF16 python embedding-bench.py
Loading BAAI/bge-m3 model on CPU...

=== 짧은 문장 쿼리 (Batch 1) 벤치마크 시작 ===
총 소요 시간: 5.2036 초
문장 1개당 평균 지연 시간: 52.0356 ms
처리 속도: 19.22 문장/초

=== 짧은 문장 쿼리 (Batch 8) 벤치마크 시작 ===
총 소요 시간: 1.8366 초
문장 1개당 평균 지연 시간: 18.3664 ms
처리 속도: 54.45 문장/초

=== 긴 문서 청크 (Batch 1) 벤치마크 시작 ===
총 소요 시간: 6.1115 초
문장 1개당 평균 지연 시간: 122.2300 ms
처리 속도: 8.18 문장/초

=== 긴 문서 청크 (Batch 8) 벤치마크 시작 ===
총 소요 시간: 4.4375 초
문장 1개당 평균 지연 시간: 88.7501 ms
처리 속도: 11.27 문장/초
(.venv) [ec2-user@ip-172-31-2-231 bench]$ python embedding-bench.py
Loading BAAI/bge-m3 model on CPU...

=== 짧은 문장 쿼리 (Batch 1) 벤치마크 시작 ===
총 소요 시간: 6.4713 초
문장 1개당 평균 지연 시간: 64.7131 ms
처리 속도: 15.45 문장/초

=== 짧은 문장 쿼리 (Batch 8) 벤치마크 시작 ===
총 소요 시간: 3.8316 초
문장 1개당 평균 지연 시간: 38.3159 ms
처리 속도: 26.10 문장/초

=== 긴 문서 청크 (Batch 1) 벤치마크 시작 ===
총 소요 시간: 12.7455 초
문장 1개당 평균 지연 시간: 254.9094 ms
처리 속도: 3.92 문장/초

=== 긴 문서 청크 (Batch 8) 벤치마크 시작 ===
총 소요 시간: 11.5515 초
문장 1개당 평균 지연 시간: 231.0299 ms
처리 속도: 4.33 문장/초
```

### 인스트럭션 확인 ###
* Graviton (c7g/c8g) — Arm bf16 지원 확인
```
grep -m1 Features /proc/cpuinfo | tr ' ' '\n' | grep -E 'bf16|i8mm|sve'
```
* bf16 있으면 → BFMMLA(Arm bf16 행렬) 가능
* i8mm → int8 MMLA, sve → Scalable Vector Extension


* Intel (c7i/c8i) — AMX bf16 지원 확인
```
grep -o -m1 -E 'amx_tile|amx_bf16|amx_int8|avx512_bf16' /proc/cpuinfo
```








