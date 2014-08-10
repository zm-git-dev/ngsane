#!/bin/bash -e

# Annotation of bam files
# author: Denis C. Bauer
# date: Jan.2013

# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME <DIR>/$INPUT_BAMANN/<SAMPLE>$ASD.bam.merg.anno.bed

echo ">>>>> Annotate BAM file "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"


function usage {
echo -e "usage: $(basename $0) -k CONFIG -f BAM -o OUTDIR [OPTIONS]

Annotating BAM file with annotations in a folder specified in the config
file

required:
  -k | --toolkit <path>     config file
  -f <file>                 bam file

options:
"
exit
}


if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f | --bam )            shift; f=$1 ;; # bam file                                                       
        --recover-from )        shift; NGSANE_RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
NGSANE_CHECKPOINT_INIT "programs"

# save way to load modules that itself loads other modules
hash module 2>/dev/null && for MODULE in $MODULE_BAMANN; do module load $MODULE; done && module list 

export PATH=$PATH_BAMANN:$PATH
echo "PATH=$PATH"

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--bedtools    --\n "$(bedtools -version)
[ -z "$(which bedtools)" ] && echo "[WARN] bedtools not detected" && exit 1

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "parameters"

# get basename of f
n=${f##*/}
SAMPLE=${n/%$ASD.bam/}

# check library variables are set
if [[ -z "$BAMANNLIB" ]]; then
    echo "[ERROR] library info not set (BAMANNLIB)"
    exit 1;
else
    echo "[NOTE] using libraries in $BAMANNLIB"
fi

# delete old bam files unless attempting to recover
if [ -z "$NGSANE_RECOVERFROM" ]; then
    [ -e $f.merg.anno.bed ] && rm $f.merg.anno.bed
    [ -e $f.anno.stats ] && rm $f.anno.stats
fi

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "recall files from tape"
	
if [ -n "$DMGET" ]; then
    dmget -a $BAMANNLIB/*
	dmget -a ${f}
fi
    
NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "bedmerge"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

	bedtools bamtobed -i $f | bedtools merge -i - -n  > $f.merg.bed

	# mark checkpoint
    NGSANE_CHECKPOINT_CHECK $f.merg.bed 

fi
 
################################################################################
NGSANE_CHECKPOINT_INIT "run annotation"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

	NAMES=""
	NUMBER=$( ls $BAMANNLIB | grep -P "(.gtf|.bed)$" | wc -l )
	ANNFILES=""
	
	for i in $(ls $BAMANNLIB | grep -P "(.gtf|.bed)$" | tr '\n' ' '); do
		NAME=$(basename $i)
		NAMES=$NAMES" "${NAME%*.*}
		ANNFILES=$ANNFILES" "$BAMANNLIB/$i
	done

	echo "[NOTE] annotate with $NAMES $ANNFILES"

   	# annotated counts and add column indicated non-annotated read counts
   	bedtools annotate -counts -i $f.merg.bed -files $ANNFILES -names $NAMES | sed 's/[ \t]*$//g' | awk '{FS=OFS="\t";if (NR==1){print $0,"unannotated"} else{ for(i=5; i<=NF;i++) j+=$i; if (j>0){print $0,0}else{print $0,1}; j=0}}' > $f.merg.anno.bed
	
	# mark checkpoint
    NGSANE_CHECKPOINT_CHECK $f.merg.anno.bed 

fi
[ -e f.merg.bed  ] && rm $f.merg.bed

################################################################################
NGSANE_CHECKPOINT_INIT "summarize"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

   	COMMAND="python ${NGSANE_BASE}/tools/sumRows.py -i $f.merg.anno.bed -l 3 -s 4 -e $(expr $NUMBER + 5) -n $(echo $NAMES | sed 's/ /,/g'),unannotated > $f.anno.stats"
	echo $COMMAND && eval $COMMAND

#    head -n 1 $f.merg.anno.bed >> $f.merg.anno.stats
    cat $f.merg.anno.bed | sort -k4gr | head -n 20 >> $f.anno.stats  
    
	# mark checkpoint
    NGSANE_CHECKPOINT_CHECK $f.anno.stats 

fi

################################################################################
[ -e $f.merg.anno.bed.dummy ] && rm $f.merg.anno.bed.dummy
echo ">>>>> Annotate BAM file - FINISHED"
echo ">>>>> enddate "`date`

