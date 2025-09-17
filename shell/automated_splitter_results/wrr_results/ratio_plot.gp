set terminal pngcairo size 1200,800 enhanced font 'Verdana,12'
set output 'automated_splitter_results/wrr_results/ratio_plot.png'
set title 'Load Admit Ratio over Time (Sample Points)'
set xlabel 'Sample Number'
set ylabel 'Load Admit Ratio'
set grid
set key top left
set yrange [0:10000]
set ytics 1000
plot 'automated_splitter_results/wrr_results/ratio_data.dat' using 1:2 with lines title 'Load Admit Ratio' linewidth 1
