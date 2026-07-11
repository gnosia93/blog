### g6e 인스턴스 온디맨드 가격 (us-east-1 기준) ###
```
  ┌──────────────┬────────┬─────────┬─────────┐
  │   인스턴스   │ GPU 수 │ 총 VRAM │ 시간당  │
  ├──────────────┼────────┼─────────┼─────────┤
  │ g6e.xlarge   │ 1      │ 48GB    │ ~$1.86  │
  ├──────────────┼────────┼─────────┼─────────┤
  │ g6e.2xlarge  │ 1      │ 48GB    │ ~$2.24  │
  ├──────────────┼────────┼─────────┼─────────┤
  │ g6e.12xlarge │ 4      │ 192GB   │ ~$10.49 │
  ├──────────────┼────────┼─────────┼─────────┤
  │ g6e.48xlarge │ 8      │ 384GB   │ ~$30.13 │
  └──────────────┴────────┴─────────┴─────────┘
```

#### LLM 목적별 어느 걸 골라야 하나 ####

- 26B QAT(~14GB), 13~14B급 → g6.xlarge($0.80)로 충분. g6e는 오버스펙.
- 30~50B급 모델을 단일 GPU로 여유롭게 → g6e.xlarge(48GB, ~$1.86) ✅ 이 지점이 g6e의 진가
- 70B급을 단일 인스턴스로 → g6e.12xlarge(192GB, ~$10.49) 또는 상위
- 아주 큰 모델(100B+)/멀티유저 서빙 → g6e.48xlarge(384GB)

####  요약
- 48GB VRAM 하나가 필요한 30~50B급 모델이라면 g6e.xlarge가 딱이에요. 24GB(g6)로는 빠듯한
모델을 한 장에 올릴 수 있죠.
- 아까 얘기하던 Gemma 26B QAT 수준이면 g6e는 과해요 — g6.xlarge가 훨씬 경제적입니다.


## EC2 GPU ##

#### 1. 해당 리전에서 g6e 오퍼링 조회 (가장 기본)
```
aws ec2 describe-instance-type-offerings \
  --location-type region \
  --filters "Name=instance-type,Values=g6e.*" \
  --region ap-northeast-2 \
  --query "InstanceTypeOfferings[].InstanceType" \
  --output table
``` 
[결과]
```
-------------------------------
|DescribeInstanceTypeOfferings|
+-----------------------------+
|  g6e.16xlarge               |
|  g6e.24xlarge               |
|  g6e.2xlarge                |
|  g6e.48xlarge               |
|  g6e.12xlarge               |
|  g6e.8xlarge                |
|  g6e.4xlarge                |
|  g6e.xlarge                 |
+-----------------------------+
```

#### 2. 특정 AZ(가용영역)까지 확인

용량은 AZ 단위로 갈리므로, 어느 AZ에 있는지 보기 위해서 아래 명령어를 실행한다.
```  
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=g6e.xlarge" \
  --region ap-northeast-2 \
  --query "InstanceTypeOfferings[].Location" \
  --output table
```
[결과]
```
-------------------------------
|DescribeInstanceTypeOfferings|
+-----------------------------+
|  ap-northeast-2a            |
|  ap-northeast-2b            |
+-----------------------------+
```

#### 3. 스펙 확인 (VRAM·vCPU 등)
```
aws ec2 describe-instance-types \
  --instance-types g6e.xlarge \
  --query "InstanceTypes[].{Type:InstanceType,vCPU:VCpuInfo.DefaultVCpus,RAM:MemoryInfo.
SizeInMiB,GPU:GpuInfo.Gpus}" \
  --output json
```
[결과]
```
[
    {
        "Type": "g6e.xlarge",
        "vCPU": 4,
        "RAM": 32768,
        "GPU": [
            {
                "Name": "L40S",
                "Manufacturer": "NVIDIA",
                "Count": 1,
                "MemoryInfo": {
                    "SizeInMiB": 45776
                }
            }
        ]
    }
]
```


#### 4. ⚠️ 쿼터(한도) 확인 — 이게 진짜 관건

오퍼링은 있는데 막상 못 띄우는 대부분의 이유는 vCPU 서비스 쿼터가 0 이어서이다. G/VT 계열은 신규 계정에서 기본 한도가 0인 경우가 많다.

```
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-DB2E81BA \
    --region ap-northeast-2 \
    --query "Quota.{Name:QuotaName,Limit:Value}" \
    --output table
```
- L-DB2E81BA = On-Demand G/VT 인스턴스 vCPU 한도 코드.
- 값이 0이면 생성 불가 → 콘솔의 Service Quotas에서 증설 요청(request increase)
- g6e.xlarge는 4 vCPU라, 최소 4 이상의 한도가 필요

[결과]
```
---------------------------------------------------
|                 GetServiceQuota                 |
+-------+-----------------------------------------+
| Limit |                  Name                   |
+-------+-----------------------------------------+
|  768.0|  Running On-Demand G and VT instances   |
+-------+-----------------------------------------+
```


#### 5. (선택) 실제 띄우기 전 안전 점검 — Dry Run

  진짜 생성 명령에 --dry-run을 붙이면 과금 없이 권한·가능 여부만 검사해요:
```  
aws ec2 run-instances \
    --instance-type g6e.xlarge \
    --image-id ami-xxxxxxxx \
    --dry-run \
    --region ap-northeast-2
```  
→ DryRunOperation이 뜨면 "실제로 실행하면 됐을 것"이라는 뜻(성공),
  UnauthorizedOperation이면 권한 문제입니다.


