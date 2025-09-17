set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output 'automated_splitter_results/wrr_results/_dev_cas1-1_iodepth1_jobs2_latency.png'
set title 'Latency over time - _dev_cas1-1_iodepth1_jobs2'
set xlabel 'Time (milliseconds)'
set ylabel 'Latency (microseconds)'
set format y "%.0f"
set grid
plot 'automated_splitter_results/wrr_results/_dev_cas1-1_iodepth1_jobs2_lat.1.log' using 1:2 with lines title 'Latency (us)'
