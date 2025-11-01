# TPCC 실험 스크립트 사용법

## 스크립트 개요

1. **tpcc_experiment.sh**: 전체 실험용 (여러 terminals, 전체 ratio 범위)
2. **tpcc_quick_test.sh**: 빠른 테스트용 (단일 terminals, 제한된 ratio 범위)

## 1. 전체 실험 스크립트 (tpcc_experiment.sh)

### 설정 변경
스크립트 상단의 변수들을 수정하여 실험 설정을 변경할 수 있습니다:

```bash
# Terminals 설정 (여러 값으로 실험 가능)
TERMINALS_LIST=(8 16)

# Ratio 범위 설정 (0~10000, 100 간격)
RATIO_START=0
RATIO_END=10000
RATIO_STEP=100
```

### 실행
```bash
cd ~/oltpbench
./tpcc_experiment.sh
```

### 결과 구조
```
results/20250916_013000/
├── tpcc_terminals8_ratio0_exp1.txt
├── tpcc_terminals8_ratio100_exp2.txt
├── ...
├── tpcc_terminals16_ratio0_exp101.txt
├── tpcc_terminals16_ratio100_exp102.txt
├── ...
└── logs/
    ├── tpcc_terminals8_ratio0_exp1.log
    ├── tpcc_terminals8_ratio100_exp2.log
    └── ...
```

## 2. 빠른 테스트 스크립트 (tpcc_quick_test.sh)

### 사용법
```bash
# 기본 사용 (terminals=8, ratio=0~1000, step=100)
./tpcc_quick_test.sh

# 커스텀 설정
./tpcc_quick_test.sh [terminals] [ratio_start] [ratio_end] [ratio_step]

# 예시
./tpcc_quick_test.sh 16 0 2000 200  # terminals=16, ratio=0~2000, step=200
```

### 실행 예시
```bash
cd ~/oltpbench

# 빠른 테스트 (5개 실험)
./tpcc_quick_test.sh 8 0 400 100

# 중간 테스트 (11개 실험)
./tpcc_quick_test.sh 16 0 1000 100

# 전체 테스트 (101개 실험)
./tpcc_quick_test.sh 8 0 10000 100
```

## 3. 실험 전 준비사항

### MySQL 설정 확인
```bash
# netcas_knob 모듈이 로드되어 있는지 확인
lsmod | grep netcas_knob

# split_ratio_permille 파일이 존재하는지 확인
ls -la /sys/module/netcas_knob/parameters/split_ratio_permille
```

### TPCC 데이터베이스 준비
```bash
# TPCC 데이터베이스 생성 및 데이터 로드
# (필요시 별도 스크립트 실행)
```

### Java 환경 확인
```bash
# Java 버전 확인
java -version

# 필요한 JAR 파일들이 있는지 확인
ls -la target/oltpbench-1.0-jar-with-dependencies.jar
ls -la mysql-connector-java-8.0.30.jar
```

## 4. 결과 분석

### 결과 요약 스크립트 실행
```bash
cd results/20250916_013000/
./summarize_results.sh
```

### 수동 결과 확인
```bash
# 특정 실험 결과 확인
cat tpcc_terminals8_ratio5000_exp51.txt

# 로그 확인
cat logs/tpcc_terminals8_ratio5000_exp51.log
```

## 5. 문제 해결

### 권한 문제
```bash
# 스크립트 실행 권한 부여
chmod +x tpcc_experiment.sh
chmod +x tpcc_quick_test.sh
```

### MySQL 연결 문제
```bash
# MySQL 상태 확인
sudo systemctl status mysql

# MySQL 재시작
sudo systemctl restart mysql
```

### netcas_knob 모듈 문제
```bash
# 모듈 상태 확인
lsmod | grep netcas_knob

# 모듈 재로드
sudo rmmod netcas_knob
sudo insmod /path/to/netcas_knob.ko
```

## 6. 실험 설정 예시

### 예시 1: 기본 실험
- Terminals: 8, 16
- Ratio: 0~10000 (100 간격)
- 총 실험 수: 202개

### 예시 2: 빠른 테스트
- Terminals: 8
- Ratio: 0~1000 (100 간격)
- 총 실험 수: 11개

### 예시 3: 세밀한 분석
- Terminals: 16
- Ratio: 0~1000 (50 간격)
- 총 실험 수: 21개
