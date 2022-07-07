aocl help > /dev/null || source ../init_env.sh


# for i in {1..5}
# do
#     echo "========"
#     echo "Run "$i
#     echo "========"

#     date
#     bin/host -ax map-ont -t 20 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null
#     # bin/host -x map-ont -t 40 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null
#     date
# done


date

#  to direct output to /dev/null
bin/host -ax map-ont -t 1 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null
# bin/host -ax map-ont -t 40 -K 5.5G /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null

# for standard run (with .sam output written to a file)
#bin/host -ax map-ont -t 4 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /share/ScratchGeneral/kisliy/minimap2_inout/hw_4thr_out.sam

# for debugging with gdb
#gdb -ex "set logging file /dev/stderr" -ex "set logging on" -ex "set disable-randomization off" --args bin/host -ax map-ont -t 4 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null 

# for debugging with valgrind
#valgrind --leak-check=yes bin/host -ax map-ont -t 4 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null

date