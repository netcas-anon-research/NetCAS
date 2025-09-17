set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output 'graph_logs_cas-NETCAS_with_contention_multi_config/_dev_cas1-1_iodepth1_jobs2/_dev_cas1-1_iodepth1_jobs2_bandwidth.png'
set title 'Bandwidth over time - _dev_cas1-1_iodepth1_jobs2 (With Server-Side Contention Timing)'
set xlabel 'Time (milliseconds)'
set ylabel 'Bandwidth (MB/s)'
set format y "%.0f"
set grid

# Add vertical lines to mark contention intervals with server-side timing
set arrow from 35000,0 to 35000,10000 nohead lc rgb "red" lw 2
set arrow from 30000,0 to 30000,10000 nohead lc rgb "red" lw 2

# Add labels for contention intervals
set label "Contention\nStarts\n(Server)" at 35000,8000 center rotate by 90 textcolor rgb "red"
set label "Contention\nEnds" at 30000,8000 center rotate by 90 textcolor rgb "red"

plot 'graph_logs_cas-NETCAS_with_contention_multi_config/_dev_cas1-1_iodepth1_jobs2/_dev_cas1-1_iodepth1_jobs2_bw.1.log' using 1:2 with lines title 'Bandwidth (MB/s)'
