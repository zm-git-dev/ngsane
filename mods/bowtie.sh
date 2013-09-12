#!/bin/bash -e

# Script to run bowtie v1 program.
# It takes comma-seprated list of files containing short sequence reads in fasta or fastq format and bowtie index files as input.
# It produces output files: read alignments in .bam format and other files.
# author: Fabian Buske
# date: August 2013

# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME <SAMPLE>.$ASD.bam


echo ">>>>> read mapping with bowtie 1"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -r REFERENCE -o OUTDIR [OPTIONS]"
exit
}


if [ ! $# -gt 3 ]; then usage ; fi

FORCESINGLE=0

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository                       
        -f | --fastq )          shift; f=$1 ;; # fastq file                                                       
        -o | --outdir )         shift; MYOUT=$1 ;; # output dir                                                     
        -s | --rgsi )           shift; SAMPLEID=$1 ;; # read group prefix
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
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
CHECKPOINT="programs"

for MODULE in $MODULE_BOWTIE; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_BOWTIE:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
PATH_IGVTOOLS=$(dirname $(which igvtools.jar))
PATH_PICARD=$(dirname $(which MarkDuplicates.jar))

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--JAVA        --\n" $(java -version 2>&1)
[ -z "$(which java)" ] && echo "[ERROR] no java detected" && exit 1
echo -e "--bowtie      --\n "$(bowtie --version)
[ -z "$(which bowtie)" ] && echo "[ERROR] no bowtie detected" && exit 1
echo -e "--samtools    --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R           --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--igvtools    --\n "$(java -jar $JAVAPARAMS $PATH_IGVTOOLS/igvtools.jar version 2>&1)
[ ! -f $PATH_IGVTOOLS/igvtools.jar ] && echo "[ERROR] no igvtools detected" && exit 1
echo -e "--PICARD      --\n "$(java -jar $JAVAPARAMS $PATH_PICARD/MarkDuplicates.jar --version 2>&1)
[ ! -f $PATH_PICARD/MarkDuplicates.jar ] && echo "[ERROR] no picard detected" && exit 1
echo -e "--bedtools --\n "$(bedtools --version)
[ -z "$(which bedtools)" ] && echo "[ERROR] no bedtools detected" && exit 1
echo -e "--samstat     --\n "$(samstat -h | head -n 2 | tail -n1)
[ -z "$(which samstat)" ] && echo "[ERROR] no samstat detected" && exit 1
echo -e "--convert     --\n "$(convert -version | head -n 1)
[ -z "$(which convert)" ] && echo "[WARN] imagemagick convert not detected" 

echo "[NOTE] set java parameters"
JAVAPARAMS="-Xmx"$(python -c "print int($MEMORY_BOWTIE*0.8)")"g -Djava.io.tmpdir="$TMP" -XX:ConcGCThreads=1 -XX:ParallelGCThreads=1" 
unset _JAVA_OPTIONS
echo "JAVAPARAMS "$JAVAPARAMS

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# check library variables are set
if [[ -z "$EXPID" || -z "$LIBRARY" || -z "$PLATFORM" ]]; then
    echo "[ERROR] library info not set (EXPID, LIBRARY, and PLATFORM): free text needed"
    exit 1;
else
    echo "[NOTE] EXPID $EXPID; LIBRARY $LIBRARY; PLATFORM $PLATFORM"
fi

# get basename of f
n=${f##*/}

# delete old bam files unless attempting to recover
if [ -z "$RECOVERFROM" ]; then
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl
fi

#is paired ?                                                                                                      
if [ "$f" != "${f/$READONE/$READTWO}" ] && [ -e ${f/$READONE/$READTWO} ] && [ "$FORCESINGLE" = 0 ]; then
    PAIRED="1"
    echo 
else
    PAIRED="0"
fi

#is ziped ?                                                                                                       
ZCAT="zcat"
if [[ ${f##*.} != "gz" ]]; then ZCAT="cat"; fi


# get encoding
if [ -z "$FASTQ_PHRED" ]; then 
    FASTQ_ENCODING=$($ZCAT $f |  awk 'NR % 4 ==0' | python $NGSANE_BASE/tools/GuessFastqEncoding.py |  tail -n 1)
    if [[ "$FASTQ_ENCODING" == *Phred33* ]]; then
        FASTQ_PHRED="--phred33-quals"    
    elif [[ "$FASTQ_ENCODING" == *Illumina* ]]; then
        FASTQ_PHRED="--phred64-quals"
    elif [[ "$FASTQ_ENCODING" == *Solexa* ]]; then
        FASTQ_PHRED="--solexa1.3-quals"
    else
        echo "[NOTE] cannot detect/don't understand fastq format: $FASTQ_ENCODING - using default"
    fi
    echo "[NOTE] $FASTQ_ENCODING fastq format detected"
fi

FASTASUFFIX=${FASTA##*.}
    

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a $(dirname $FASTA)/*
	dmget -a ${f/$READONE/"*"}
fi
    
echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="generating the index files"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    if [ ! -e ${FASTA/.${FASTASUFFIX}/}.1.ebwt ]; then echo ">>>>> make .ebwt"; bowtie-build $FASTA ${FASTA/.${FASTASUFFIX}/}; fi
    if [ ! -e $FASTA.fai ]; then echo "[NOTE] make .fai"; samtools faidx $FASTA; fi

    # mark checkpoint
    if [ -f ${FASTA/.${FASTASUFFIX}/}.1.ebwt ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi 

################################################################################
CHECKPOINT="run bowtie"

if [ $PAIRED == "0" ]; then 
    READS="$f"
    let FASTQREADS=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
else 

    READS="-1 $f -2 ${f/$READONE/$READTWO}"
    READ1=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
    READ2=`$ZCAT ${f/$READONE/$READTWO} | wc -l | gawk '{print int($1/4)}' `
    let FASTQREADS=$READ1+$READ2
fi

#readgroup
FULLSAMPLEID=$SAMPLEID"${n/%$READONE.$FASTQ/}"
RG="--sam-RG \"ID:$EXPID\" --sam-RG \"SM:$FULLSAMPLEID\" --sam-RG \"LB:$LIBRARY\" --sam-RG \"PL:$PLATFORM\""


if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

	# Unpaired
	if [ $PAIRED == "0" ]; then
        echo "[NOTE] SINGLE READS"

        RUN_COMMAND="$ZCAT $f | bowtie $RG $BOWTIEADDPARAM $FASTQ_PHRED --threads $CPU_BOWTIE --un $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} --max $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} --sam $BOWTIE_OPTIONS ${FASTA/.${FASTASUFFIX}/} - $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}"

	#Paired
    else
        echo "[NOTE] PAIRED READS"
        # clever use of named pipes to avoid fastq unzipping
        [ -e $MYOUT/${n}_pipe ] && rm $MYOUT/${n}_pipe
        [ -e $MYOUT/${n/$READONE/$READTWO}_pipe ] && rm $MYOUT/${n/$READONE/$READTWO}_pipe
        mkfifo $MYOUT/${n}_pipe $MYOUT/${n/$READONE/$READTWO}_pipe
        
        $ZCAT $f > $MYOUT/${n}_pipe &
        $ZCAT ${f/$READONE/$READTWO} > $MYOUT/${n/$READONE/$READTWO}_pipe &
        
		RUN_COMMAND="bowtie $RG $BOWTIEADDPARAM $FASTQ_PHRED --threads $CPU_BOWTIE --un $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} --max $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} --sam $BOWTIE_OPTIONS ${FASTA/.${FASTASUFFIX}/} -1 $MYOUT/${n}_pipe -2 $MYOUT/${n/$READONE/$READTWO}_pipe $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}"

    fi
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    # cleanup
    [ -e $MYOUT/${n}_pipe ] && rm $MYOUT/${n}_pipe
    [ -e $MYOUT/${n/$READONE/$READTWO}_pipe ] && rm $MYOUT/${n/$READONE/$READTWO}_pipe

    # mark checkpoint
    if [ -f $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="bam conversion and sorting"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    # create bam files for discarded reads and remove fastq files    
    if [ $PAIRED == "1" ]; then
        if [ -e $MYOUT/${n/%$READONE.$FASTQ/.${UNM}_1.fq} ]; then
            java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
                FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.${UNM}_1.fq} \
                FASTQ2=$MYOUT/${n/%$READONE.$FASTQ/.${UNM}_2.fq} \
                OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} \
                QUALITY_FORMAT=Standard \
                SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
                READ_GROUP_NAME=null \
                QUIET=TRUE \
                VERBOSITY=ERROR
            samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp}
            mv $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam}
        fi
    
        if [ -e $MYOUT/${n/%$READONE.$FASTQ/.${MUL}_1.fq} ]; then
            java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
                FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}_1.fq} \
                FASTQ2=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}_2.fq} \
                OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}.bam} \
                QUALITY_FORMAT=Standard \
                SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
                READ_GROUP_NAME=null \
                QUIET=TRUE \
                VERBOSITY=ERROR
        
            samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp}
            mv $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam}
        fi
    else
        if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} ]; then
            java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
                FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} \
                OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} \
                QUALITY_FORMAT=Standard \
                SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
                READ_GROUP_NAME=null \
                QUIET=TRUE \
                VERBOSITY=ERROR
            samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp}
            mv $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam}
        fi
    
        if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} ]; then
            java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
                FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} \
                OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} \
                QUALITY_FORMAT=Standard \
                SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
                READ_GROUP_NAME=null \
                QUIET=TRUE \
                VERBOSITY=ERROR
        
            samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp}
            mv $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} 
        fi
    fi
    # cleanup
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.${UNM}_1.fq} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.${UNM}_*.fq}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.${MUL}_1.fq} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.${MUL}_*.fq}
        
    # continue for normal bam file conversion                                                                         
    samtools view -Sbt $FASTA.fai $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam} > $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}
    
    samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam} $MYOUT/${n/%$READONE.$FASTQ/.ash}
    
    if [ "$PAIRED" = "1" ]; then
        # fix mates
        samtools sort -n $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp
        samtools fixmate $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp.bam - | samtools sort - $MYOUT/${n/%$READONE.$FASTQ/.ash}
        [ -e $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp.bam ] && rm $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp.bam
    fi

    # mark checkpoint
    if [ -f $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="mark duplicates"
# create bam files for discarded reads and remove fastq files
if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
   
    if [ ! -e $MYOUT/metrices ]; then mkdir -p $MYOUT/metrices ; fi
    THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files                                        
    mkdir -p $THISTMP
    java $JAVAPARAMS -jar $PATH_PICARD/MarkDuplicates.jar \
        INPUT=$MYOUT/${n/%$READONE.$FASTQ/.ash.bam} \
        OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} \
        METRICS_FILE=$MYOUT/metrices/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl \
        AS=true \
        VALIDATION_STRINGENCY=LENIENT \
        TMP_DIR=$THISTMP
    [ -d $THISTMP ] && rm -r $THISTMP
    samtools index $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}

    # mark checkpoint
    if [ -f $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="statistics"                                                                                                

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    STATSOUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats
    samtools flagstat $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} > $STATSOUT
    
    if [ -n $SEQREG ]; then
        echo "#custom region" >> $STATSOUT
        echo $(samtools view -c -F 4 $MYOUT/${n/%$READONE.$FASTQ/.ash.bam} $SEQREG )" total reads in region " >> $STATSOUT
        echo $(samtools view -c -f 3 $MYOUT/${n/%$READONE.$FASTQ/.ash.bam} $SEQREG )" properly paired reads in region " >> $STATSOUT
    fi

    # mark checkpoint
    if [ -f $STATSOUT ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="calculate inner distance"                                                                                                

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
    mkdir $THISTMP
    java $JAVAPARAMS -jar $PATH_PICARD/CollectMultipleMetrics.jar \
        INPUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} \
        REFERENCE_SEQUENCE=$FASTA \
        OUTPUT=$MYOUT/metrices/${n/%$READONE.$FASTQ/.$ASD.bam} \
        VALIDATION_STRINGENCY=LENIENT \
        PROGRAM=CollectAlignmentSummaryMetrics \
        PROGRAM=CollectInsertSizeMetrics \
        PROGRAM=QualityScoreDistribution \
        TMP_DIR=$THISTMP
      
    # create pdfs
    if [ -n "$(which convert)" ]; then 
        for im in $( ls $MYOUT/metrices/*.pdf ); do
            convert $im ${im/pdf/jpg}
        done
    fi
    [ -e $THISTMP ] && rm -r $THISTMP

    # mark checkpoint
    [ -f $MYOUT/metrices/${n/%$READONE.$FASTQ/.$ASD.bam}.alignment_summary_metrics ] && echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi


################################################################################
CHECKPOINT="coverage track"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar count $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam.cov.tdf} ${FASTA/.$FASTASUFFIX/.genome}
    
    # mark checkpoint
    if [ -f $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam.cov.tdf} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="samstat"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    samstat $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}

    # mark checkpoint
    if [ -f $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi


################################################################################
CHECKPOINT="verify"    
    
BAMREADS=`head -n1 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats | cut -d " " -f 1`
if [ "$BAMREADS" = "" ]; then let BAMREADS="0"; fi
if [ $BAMREADS -eq $FASTQREADS ]; then
    echo "-----------------> PASS check mapping: $BAMREADS == $FASTQREADS"
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.ash.bam} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.ash.bam}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam}
    [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam} ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam}
else
    echo -e "[ERROR] We are loosing reads from .fastq -> .bam in $f: \nFastq had $FASTQREADS Bam has $BAMREADS"
    exit 1
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
[ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dummy ] && rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dummy
echo ">>>>> read mapping with bowtie 1 - FINISHED"
echo ">>>>> enddate "`date`
