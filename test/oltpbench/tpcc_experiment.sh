#!/bin/bash

# TPCC 실험 스크립트
# 사용법: ./tpcc_experiment.sh

set -e  # 에러 발생 시 스크립트 종료

# ==================== 실험 설정 변수 ====================
# Terminals 설정 (여러 값으로 실험 가능)
TERMINALS_LIST=(32)

# Ratio 범위 설정 (0~10000, 100 간격)
RATIO_START=3100
RATIO_END=10000
RATIO_STEP=100

# 실험 기본 설정
SCALE_FACTOR=1  # 실험 로그 간격
EXPERIMENT_NAME="tpcc_ocf_mf"

# ==================== 디렉토리 설정 ====================
# 결과 저장 디렉토리
RESULTS_DIR="results/$EXPERIMENT_NAME"
mkdir -p "$RESULTS_DIR"

# 로그 디렉토리
LOG_DIR="$RESULTS_DIR/logs"
mkdir -p "$LOG_DIR"

echo "=== TPCC 실험 시작 ==="
echo "결과 저장 디렉토리: $RESULTS_DIR"
echo "Terminals: ${TERMINALS_LIST[*]}"
echo "Ratio 범위: $RATIO_START ~ $RATIO_END (간격: $RATIO_STEP)"
echo ""

# ==================== 실험 함수 ====================
run_experiment() {
    local terminals=$1
    local ratio=$2
    
    echo "실험: Terminals=$terminals, Ratio=$ratio"
    
    # 1. Ratio 설정
    echo "Ratio 설정 중: $ratio"
    echo "$ratio" | sudo tee /sys/module/netcas_knob/parameters/split_ratio_permille > /dev/null
    
    # 잠시 대기 (설정 적용 시간)
    sleep 2

    # Reset statistics using casadm -Z
    echo "Resetting statistics..."
    sudo casadm -Z -i 1 || echo "Warning: casadm reset failed, continuing..."

    # 잠시 대기 (설정 적용 시간)
    sleep 2
    
    # 2. Config 파일 업데이트
    local config_file="config/tpcc_config_mysql_temp.xml"
    cp config/tpcc_config_mysql.xml "$config_file"
    
    # sed를 사용해서 terminals 값 변경
    sed -i "s/<terminals>[0-9]*<\/terminals>/<terminals>$terminals<\/terminals>/" "$config_file"
    
    # 3. Terminals별 디렉토리 생성
    local terminals_dir="$RESULTS_DIR/terminals${terminals}"
    mkdir -p "$terminals_dir"
    
    # 4. 결과 파일명 생성
    local result_base_name="tpcc_terminals${terminals}_ratio${ratio}"
    local log_file="$LOG_DIR/${result_base_name}.log"
    
    # 4. TPCC 실행 (기본 results 디렉토리에 생성)
    echo "TPCC 실행 중..."
    java -Dlog4j.configuration=log4j.properties \
         -cp target/oltpbench-1.0-jar-with-dependencies.jar:mysql-connector-java-8.0.30.jar \
         com.oltpbenchmark.DBWorkload \
         -b tpcc -c "$config_file" \
         --execute=true -s $SCALE_FACTOR -o "$result_base_name" \
         > "$log_file" 2>&1

    # 잠시 대기 (설정 적용 시간)
    sleep 10
    
    # 5. 임시 config 파일 삭제
    rm -f "$config_file"
    
    # 6. 결과 파일을 terminals별 디렉토리로 이동
    local source_csv="results/${result_base_name}.csv"
    local source_res="results/${result_base_name}.res"
    local dest_csv="$terminals_dir/${result_base_name}.csv"
    local dest_res="$terminals_dir/${result_base_name}.res"
    
    # 7. 결과 확인 및 이동
    if [ -f "$source_csv" ] && [ -f "$source_res" ]; then
        mv "$source_csv" "$dest_csv"
        mv "$source_res" "$dest_res"
        echo "실험 완료: ${dest_csv}, ${dest_res}"
    elif [ -f "$source_csv" ]; then
        mv "$source_csv" "$dest_csv"
        echo "실험 완료: ${dest_csv} (res 파일 없음)"
    elif [ -f "$source_res" ]; then
        mv "$source_res" "$dest_res"
        echo "실험 완료: ${dest_res} (csv 파일 없음)"
    else
        echo "실험 실패: 결과 파일이 생성되지 않음"
    fi
    
    echo "---"
}

# ==================== 실험 실행 ====================
# Terminals별로 실험
for terminals in "${TERMINALS_LIST[@]}"; do
    echo "=== Terminals: $terminals 실험 시작 ==="
    
    # Ratio별로 실험
    for ((ratio=$RATIO_START; ratio<=$RATIO_END; ratio+=$RATIO_STEP)); do
        run_experiment $terminals $ratio
        
        # 실험 간 잠시 대기
        sleep 1
    done
    
    echo "=== Terminals: $terminals 실험 완료 ==="
    echo ""
done

# ==================== 결과 요약 ====================
echo "=== 실험 완료 ==="
echo "결과 디렉토리: $RESULTS_DIR"
echo ""

# 결과 파일 목록 출력
echo "생성된 결과 파일들:"
for terminals in "${TERMINALS_LIST[@]}"; do
    terminals_dir="$RESULTS_DIR/terminals${terminals}"
    if [ -d "$terminals_dir" ]; then
        echo "=== Terminals $terminals ==="
        echo "CSV 파일들:"
        find "$terminals_dir" -name "*.csv" | sort
        echo "RES 파일들:"
        find "$terminals_dir" -name "*.res" | sort
        echo ""
    fi
done

echo ""
echo "실험 로그들:"
find "$LOG_DIR" -name "*.log" | sort

# ==================== 결과 요약 스크립트 생성 ====================
summary_script="$RESULTS_DIR/summarize_results.sh"
cat > "$summary_script" << 'EOF'
#!/bin/bash
# 결과 요약 스크립트

echo "=== TPCC 실험 결과 요약 ==="
echo ""

# Terminals별 디렉토리 처리
for terminals_dir in terminals*; do
    if [ -d "$terminals_dir" ]; then
        echo "=== $terminals_dir 처리 중 ==="
        cd "$terminals_dir"
        
        # Throughput 결과를 저장할 CSV 파일
        summary_csv="../${terminals_dir}_throughput_summary.csv"
        echo "ratio,throughput" > "$summary_csv"
        
        # RES 파일들에서 throughput 추출
        for file in *.res; do
            if [ -f "$file" ]; then
                # 파일명에서 ratio 추출 (예: tpcc_terminals8_ratio2000.res -> 2000)
                ratio=$(echo "$file" | sed 's/.*ratio\([0-9]*\)\.res/\1/')
                
                # throughput 값들 추출 (헤더 제외)
                throughputs=$(tail -n +2 "$file" | cut -d',' -f2 | tr -d ' ')
                
                # 평균 계산
                if [ -n "$throughputs" ]; then
                    avg_throughput=$(echo "$throughputs" | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}')
                    echo "$ratio,$avg_throughput" >> "$summary_csv"
                    echo "  $file: ratio=$ratio, avg_throughput=$avg_throughput"
                fi
            fi
        done
        
        echo "  요약 파일 생성: $summary_csv"
        cd ..
        echo ""
    fi
done

echo "=== 전체 요약 완료 ==="
echo "생성된 요약 파일들:"
ls -la *_throughput_summary.csv 2>/dev/null || echo "요약 파일이 없습니다."
EOF

chmod +x "$summary_script"
echo "결과 요약 스크립트 생성: $summary_script"
echo "사용법: cd $RESULTS_DIR && ./summarize_results.sh"
