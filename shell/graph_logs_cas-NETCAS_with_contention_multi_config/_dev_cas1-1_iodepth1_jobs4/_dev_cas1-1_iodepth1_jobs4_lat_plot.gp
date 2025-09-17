set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output 'graph_logs_cas-NETCAS_with_contention_multi_config/_dev_cas1-1_iodepth1_jobs4/_dev_cas1-1_iodepth1_jobs4_latency.png'
set title 'Latency over time - _dev_cas1-1_iodepth1_jobs4 (With Server-Side Contention Timing)'
set xlabel 'Time (milliseconds)'
set ylabel 'Latency (microseconds)'
set format y "%.0f"
set grid

# Add vertical lines to mark contention intervals with server-side timing
set arrow from 36000,0 to 36000,10000 nohead lc rgb "red" lw 2
set arrow from 30000,0 to 30000,10000 nohead lc rgb "red" lw 2

# Add labels for contention intervals
set label "Contention\nStarts\n(Server)" at 36000,8000 center rotate by 90 textcolor rgb "red"
set label "Contention\nEnds" at 30000,8000 center rotate by 90 textcolor rgb "red"

plot 'graph_logs_cas-NETCAS_with_contention_multi_config/_dev_cas1-1_iodepth1_jobs4/_dev_cas1-1_iodepth1_jobs4_lat.1.log' using 1:2 with lines title 'Latency (us)'
