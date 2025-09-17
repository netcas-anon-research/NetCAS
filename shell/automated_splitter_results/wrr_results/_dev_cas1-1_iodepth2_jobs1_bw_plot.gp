set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output 'automated_splitter_results/wrr_results/_dev_cas1-1_iodepth2_jobs1_bandwidth.png'
set title 'Bandwidth over time - _dev_cas1-1_iodepth2_jobs1'
set xlabel 'Time (milliseconds)'
set ylabel 'Bandwidth (MB/s)'
set format y "%.0f"
set grid
plot 'automated_splitter_results/wrr_results/_dev_cas1-1_iodepth2_jobs1_bw.1.log' using 1:2 with lines title 'Bandwidth (MB/s)'
