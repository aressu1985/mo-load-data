#!/usr/bin/env bash

pip3 install shyaml

#if [[ $# -eq 0 ]];then
#    echo "No parameters provided,please use -H to get help. "
#fi

TIMES=1
STATUS=0

WORKSPACE=$(cd `dirname $0`; pwd)
SERVER="127.0.0.1"
PORT=6001
USER=dump
PASS=111
CONFIG=cases
TIMES=1
CHECK="true"

while getopts ":h:P:u:p:c:t:rgH" opt
do
    case $opt in
        h)
        SERVER="${OPTARG}"
        ;;
        P)
        PORT=${OPTARG}
        ;;
        u)
        USER="${OPTARG}"
        ;;
        p)
        PASS="${OPTARG}"
        ;;
        c)
        CONFIG="${OPTARG}"
        ;;
        r)
        REPLACE="true"
	      ;;
        t)
        expr ${OPTARG} "+" 10 &> /dev/null
        if [ $? -ne 0 ]; then
          echo 'The times ['${OPTARG}'] is not a number'
          exit 1
        fi
        TIMES="${OPTARG}"
        ;;
        g)
        CHECK="false"
        ;;
        H)
        echo -e "Usage:　bash load.sh [option] [param] ...\nExcute mo load data task"
        echo -e "   -h  mo server address"
        echo -e "   -P  mo server port"
        echo -e "   -u  mo server username"
        echo -e "   -p  mo server password of the user[-u]"
        echo -e "   -c  designate the case config file that the load.sh will run, if None, will run all config in the dir ./cases/"
        echo -e "   -r  means tool will re-create table before loading"
	      echo -e "   -t  set times that test will run for" 
	      echo -e "Examples:"
        echo "   bash load.sh"
	      echo -e "   bash run.sh -c cases/xxx.yml "
        echo -e "   bash run.sh -h 127.0.0.1 -udump -p111 -P6001 -c cases/xxx.yml"
	      echo "For more support,please email to sudong@matrixorigin.io"
        exit 1
        ;;
        ?)
        echo "Unkown parameter,please use -H to get help."
        exit 1;;
    esac
done

function load() {
    local cfg=$1
    local db=`cat ${cfg} | shyaml get-value db`
    local table=`cat ${cfg} | shyaml get-value table`
    local count=`cat ${cfg} | shyaml get-value count`
    local file=`cat ${cfg} | shyaml get-value path`
    local ddl=`cat ${cfg} | shyaml get-value ddl`
    local terminated=`cat ${cfg} | shyaml get-value terminated`
    local s3=`cat ${cfg} | shyaml get-value s3`
    local name=`basename ${cfg} .yml`
    if [ "${s3}" != "true" ]; then
      file1=${WORKSPACE}/data/${file}
      if [ ! -f "${file1}" ]; then
          file=${file}
      else
          file=${file1}	      
      fi
      #echo $file
    fi
    
    local sql="load data infile '${file}' into table ${db}.${table} FIELDS TERMINATED BY '${terminated}' LINES TERMINATED BY '\n';"
    echo -e "`date +'%Y-%m-%d %H:%M:%S'` [${name}]"
    echo -e "`date +'%Y-%m-%d %H:%M:%S'` Start to load data from file ${file} into table ${db}.${table},please wait....." | tee -a ${WORKSPACE}/run.log
    echo -e "`date +'%Y-%m-%d %H:%M:%S'` ${sql}"
    
    startTime=`date +%s.%N`
    result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "${sql}" 2>&1`
    if [ $? -eq 0 ];then
      endTime=`date +%s.%N`
      getTiming $startTime $endTime
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The data for table ${db}.${table} has been loaded successfully, and cost: ${cost}" | tee -a ${WORKSPACE}/run.log
      echo "${name}:${cost}" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
      
      if [ "${CHECK}" = "true" ];then
        check $cfg
        if [ $? -eq 1 ];then
          STATUS=1
	        echo "${name}:Failed" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
        else
	        echo "${name}:Success" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
        fi
      else
        echo "${name}:Success" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
      fi
      
      echo -e "" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
    else
      STATUS=1
      echo "`date +'%Y-%m-%d %H:%M:%S'` ${result}"
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The data for table ${db}.${table} has failed to be loaded." | tee -a ${WORKSPACE}/run.log
      echo "${name}: ${result}" | awk 'NR>1' | tee -a >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
      echo -e "" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
    fi

    if [ $STATUS -eq 1 ];then
        echo "`date +'%Y-%m-%d %H:%M:%S'` This test for [${name}] has been executed failed, more info, please see the log" | tee -a ${WORKSPACE}/run.log
    else
	echo "`date +'%Y-%m-%d %H:%M:%S'` This test for [${name}] has been executed successfully" | tee -a ${WORKSPACE}/run.log
    fi

    echo -e ""

}

function getTiming(){
    start=$1
    end=$2

    start_s=`echo $start | cut -d '.' -f 1`
    start_ns=`echo $start | cut -d '.' -f 2`
    end_s=`echo $end | cut -d '.' -f 1`
    end_ns=`echo $end | cut -d '.' -f 2`

    time_micro=$(( (10#$end_s-10#$start_s)*1000000 + (10#$end_ns/1000 - 10#$start_ns/1000) ))
    time_ms=`expr $time_micro/1000  | bc `

    cost=${time_ms}
}

function check() {
    local cfg=$1
    local db=`cat ${cfg} | shyaml get-value db`
    local table=`cat ${cfg} | shyaml get-value table`
    local count=`cat ${cfg} | shyaml get-value count`
    local sql="select count(*) from ${db}.${table};"
    local result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} {db} -e "${sql}" 2>&1`
    local rcount=`echo "${result}" | awk 'NR>2'`
    expr ${rcount} "+" 10 &> /dev/null
    if [ $? -ne 1 ]; then
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` Failed to query table[${db}.${table}] size, cause:" | tee -a ${WORKSPACE}/run.log
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` ${result}" | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    
    if [ "${rcount}" != "${count}" ]; then
      STATUS=1
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The table[${db}.${table}] size is not correct, expect:${count}, but real[${rcount}]" | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    return 0
}

function createSchema() {
    local cfg=$1
    local db=`cat ${cfg} | shyaml get-value db`
    local table=`cat ${cfg} | shyaml get-value table`
    local count=`cat ${cfg} | shyaml get-value count`
    local ddl=`cat ${cfg} | shyaml get-value ddl`
    local drop="drop table if exists ${db}.${table}" 
    local cdb="create database if not exists ${db};"
    local result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "${cdb}" 2>&1`
    if [ $? -ne 0 ];then
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The database ${db} cant not be created. Error: ${result}"  | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    
    if [ "${REPLACE}" = "true" ];then
      result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "${drop}" 2>&1`
      if [ $? -ne 0 ];then
	      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The table ${db}.${table} cant not be drop. Error: ${result}"  | tee -a ${WORKSPACE}/run.log
        return 1
      fi
    fi

    result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "use ${db};${ddl}" 2>&1`
    if [ $? -ne 0 ];then
      echo -e "`date +'%Y-%m-%d %H:%M:%S'` The table ${db}.${table} cant not be created. Error: ${result}"  | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    
    return 0;
    
}

function listCases() {
    local dir=$1
    for file in ${dir}/*
    do
      if [ -f ${file} ];then
        CFGLIST=(${CFGLIST[*]} $file)
      else 
        listCases $file
      fi
    done
}


dir=${CONFIG}


if [ -e ${WORKSPACE}/report ];then
    rm -rf ${WORKSPACE}/report/*
else
    mkdir p ${WORKSPACE}/report/
fi

if [ "${TIMES}" = "1" ];then
  if [ -d ${dir} ];then
    listCases ${dir}
    for cfg in ${CFGLIST[*]}
    do
      createSchema $cfg
      load $cfg
    done
                  
    if [ $STATUS -eq 1 ];then
      echo "`date +'%Y-%m-%d %H:%M:%S'` This test has been failed, more info, please see the log" | tee -a ${WORKSPACE}/run.log
      exit 1
    fi  
    exit 0
  else
    createSchema ${dir}
    load ${dir}                  
    if [ $STATUS -eq 1 ];then
      echo "`date +'%Y-%m-%d %H:%M:%S'` This test has been failed, more info, please see the log" | tee -a ${WORKSPACE}/run.log
      exit 1
    fi  
    exit 0
  fi
else
  echo "`date +'%Y-%m-%d %H:%M:%S'` This test will be run for ${TIMES} times"
  echo -e ""
    for i in $(seq 1 ${TIMES})
    do
      echo "`date +'%Y-%m-%d %H:%M:%S'` The ${i} turn has been stared, please wait......." | tee -a ${WORKSPACE}/run.log
      unset CFGLIST
      if [ -d ${dir} ];then
        listCases ${dir}
        for cfg in ${CFGLIST[*]}
        do
          createSchema $cfg
          load $cfg
        done
      
        echo "`date +'%Y-%m-%d %H:%M:%S'` The ${i} turn test has ended, and test report is in ./report/${i} dir." | tee -a ${WORKSPACE}/run.log
        echo -e ""
        
        mkdir -p ${WORKSPACE}/report/${i}/
        mv ${WORKSPACE}/report/*.txt ${WORKSPACE}/report/${i}/            
        
      else
        createSchema ${dir}
        load ${dir}
    fi
    done
    if [ $STATUS -eq 1 ];then
      echo "`date +'%Y-%m-%d %H:%M:%S'` This test has been executed failed, more info, please see the log" | tee -a ${WORKSPACE}/run.log
      exit 1
    fi
    echo "`date +'%Y-%m-%d %H:%M:%S'` This test has been executed successfully, more info, please see the log" | tee -a ${WORKSPACE}/run.log
    exit 0
fi
