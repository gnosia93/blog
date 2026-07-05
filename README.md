# blog

* https://www.anyscale.com/blog/architecting-multimodal-data-pipelines-that-scale-with-ray


#### 1. aws CLI 설치 ####
```bash
brew install awscli
brew upgrade awscli

aws --version
```

#### 2. EC2 세션 매니저 설치 ####
```bash
brew install --cask session-manager-plugin

session-manager-plugin
```

#### 3. 리전 조회 및 설정 ####
```bash
aws configure get region
aws configure set region us-east-1
```

#### 4. EC2 인스턴스 프로파일 생성 ####
ssh key 없이 AWS 시스템 매니저를 통해서 EC2 인스턴스에 접속하기 위해서 생성한다.
```bash
# 신뢰 정책 파일 (ec2가 이 역할을 맡을 수 있게)
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# 역할 생성 + 정책 연결
aws iam create-role --role-name EC2-SSM-Role \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy --role-name EC2-SSM-Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# 인스턴스 프로파일 생성 후 역할 담기
aws iam create-instance-profile --instance-profile-name EC2-SSM-Profile
aws iam add-role-to-instance-profile \
  --instance-profile-name EC2-SSM-Profile --role-name EC2-SSM-Role
```
생성된 프로파일을 조회한다.
```
aws iam get-instance-profile --instance-profile-name EC2-SSM-Profile
```

#### 5. EC2 인스턴스 생성 ####
* 지원여부 조회
```
aws ec2 describe-instance-type-offerings \
  --location-type region \
  --filters "Name=instance-type,Values=c9g.2xlarge"
```

* 생성하기
```
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query "Parameter.Value" --output text)
echo "AMI ID: ${AMI_ID}"

aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type c9g.2xlarge \
  --iam-instance-profile Name=EC2-SSM-Profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=graviton-c9g}]'
```

#### 6. 접속하기 ####
```
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{ID:InstanceId,Ping:PingStatus,Name:ComputerName}" \
  --output table

aws ec2 describe-instances \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,PublicIP:PublicIpAddress,PublicDNS:PublicDnsName,PrivateIP:PrivateIpAddress}" \
  --output table

aws ssm start-session \
  --target i-0123456789abcdef0
```
* 유저 전화 및 패키지 설치 
```
sudo su - ec2-user

uname -m               
cat /etc/os-release    
sudo yum install -y git
```
