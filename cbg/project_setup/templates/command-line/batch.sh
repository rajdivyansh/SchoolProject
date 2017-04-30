#!/bin/bash
########################################################################
# Batch Job Control Script
#
# This script starts/stops/restarts/gives status of batch jobs
#
########################################################################


BASE_DIR=`dirname "$0"`
BASE_DIR=`cd "$BASE_DIR/.." ; pwd`

## first try to get variables from setenv.sh if they're explicitly set
if [ -r "$BASE_DIR"/bin/setenv.sh ]; then
  . "$BASE_DIR"/bin/setenv.sh
fi

if [ -n "$2" ]; then
  valid=false
  for i in ${INSTANCES//,/ }
  do
    if [ "$i" = "$2" ]; then
      valid=true
    fi
  done
  
  if $valid; then
    INSTANCES=$2
  else
    echo "ERROR: invalid or unknown instance: $2"
    exit
  fi
fi

has_instances=false
if [ -n "$INSTANCES" ]; then
  has_instances=true
fi

if [ -n "$2" ]; then
    INSTANCES=$2
fi

start()
{
  cd $BASE_DIR

  if $has_instances; then
    # instances are comma separated.  change to space sep so looping works
    for i in ${INSTANCES//,/ }
    do
      start_instance $i
    done
  else
    start_instance
  fi

}

start_instance()
{
  INSTANCE=$1
  PID_FILE=$(pid_file $INSTANCE)
  THIS_APP=$(this_app $INSTANCE)
  
  if [ -r "$BASE_DIR"/bin/setenv-$INSTANCE.sh ]; then
    . "$BASE_DIR"/bin/setenv-$INSTANCE.sh
  fi


  if $(instance_running $INSTANCE); then
    echo "WARNING: $THIS_APP already running with pid" `cat $PID_FILE`
    return 
  fi
  echo "Starting $THIS_APP"

  ## if not set in setenv.sh, set these env vars  
  if [ -z "$LIB_DIR" ]; then
      LIB_DIR="$BASE_DIR/lib"
  fi;

  if [ -z "$CONFIG_DIR" ]; then
    CONFIG_DIR="$BASE_DIR/config"
  fi

  ## unset any existing classpath, then reset w/ the jar files
  CP= 
  COLON=
  for file in ${LIB_DIR}/*.jar
  do
    CP=${CP}$COLON$file
    COLON=:
  done

  if [ -z "$LOG_CONFIG_FILE" ]; then
    LOG_CONFIG_FILE=${CONFIG_DIR}/$APP_NAME-log4j.xml
  fi

  LOG_PROVIDER_CONFIG_PROP="-Dlog4j.configurationFile=file:${LOG_CONFIG_FILE} -Dlog4j.configuration=file:${LOG_CONFIG_FILE} -Dlogback.configurationFile=file:${LOG_CONFIG_FILE}"
  
  if [ -z "$DATABASE_TYPE" ]; then
    DATABASE_TYPE=oracle
  fi

  # should probably add a way to configure props file name in setenv.sh
  if $has_instances; then    
    PROPS_FILE=$CONFIG_DIR/$APP_NAME-$INSTANCE.properties
  else
    PROPS_FILE=$CONFIG_DIR/$APP_NAME.properties
  fi

  # this assumes the log file name contains an instance number (if there are intances) in the log file name (${log.dir}/application-name-${process_id}.log)
  if [ -z "$LOG_DIR" ]; then
    LOG_DIR="${BASE_DIR}/logs/"
  fi

  if [ ! -e "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
  fi

  if $has_instances; then
    OUT_FILE=$LOG_DIR/$APP_NAME-$INSTANCE.out
  else
    OUT_FILE=$LOG_DIR/$APP_NAME.out
  fi

  if [ -z "$JAVA_HOME" ]; then
    JAVA_HOME=/usr/java/default/
  fi

  # I think these need to be quoted to take care of strange chars (spaces) in the path
  JVM_USR_ARGS="-Dlog.dir=${LOG_DIR} ${LOG_PROVIDER_CONFIG_PROP} -DPropertiesFileName=${PROPS_FILE} -DPropFileLocation=${PROPS_FILE} -Dprop.file=$PROPS_FILE -Ddatabase.type=$DATABASE_TYPE -Djava.security.egd=file:///dev/urandom "

  if $has_instances; then
    JVM_USR_ARGS="$JVM_USR_ARGS -Dprocess_id=${INSTANCE}"
  fi

  if [ ! -z "${JMX_PORT}" -a ! -z "${JMX_RMISERVER_PORT}" ]; then
    JVM_USR_ARGS="$JVM_USR_ARGS -Dmonitor.jmxremote.port=${JMX_PORT} -Dmonitor.jmxremote.rmiserver.port=${JMX_RMISERVER_PORT}"
    JVM_USR_ARGS="$JVM_USR_ARGS -Dmonitor.jmxremote.ssl.enable=false "
    JVM_USR_ARGS="$JVM_USR_ARGS -javaagent:${JMX_AGENT:-${LIB_DIR}/monitor-jmx-agent-1.3.jar}"
  fi

  if [ ! -z "$LOG_JVM_CLASSLOADER" ]; then
    JVM_USR_ARGS="$JVM_USR_ARGS -verbose:class"
  fi

  if [ -z "$JVM_ARGS" ]; then
    JVM_ARGS="-Xms256m -Xmx1024m -XX:PermSize=64m -XX:MaxPermSize=128m -XX:MaxMetaspaceSize=128m -XX:+IgnoreUnrecognizedVMOptions -Xdump:none -Xdump:system:none "
  fi
  
  # invoke the process
  nohup $JAVA_HOME/bin/java -cp ${CP}  ${JVM_ARGS}  ${DEBUG_ARGS} ${JVM_USR_ARGS} ${MAIN_CLASS} ${PROPS_FILE} >> $OUT_FILE 2>&1 < /dev/null &
  echo $! > $PID_FILE
}

stop()
{
  cd $BASE_DIR

  if $has_instances; then
    # instances are comma separated.  change to space sep so looping works
    for i in ${INSTANCES//,/ }
    do
      stop_instance $i
    done
  else
    stop_instance
  fi

}

stop_instance()
{
  INSTANCE=$1
  PID_FILE=$(pid_file $1)
  
  if [ -r "$BASE_DIR"/bin/setenv-$INSTANCE.sh ]; then
    . "$BASE_DIR"/bin/setenv-$INSTANCE.sh
  fi


  THIS_APP=$APP_NAME
  if $has_instances; then
    THIS_APP="$THIS_APP instance $INSTANCE"
  fi

  if ! $(instance_running $INSTANCE); then
    echo "WARNING: $THIS_APP is not running"
    return 
  fi

  echo "Stopping $THIS_APP with pid" `cat $PID_FILE`
  PID_NUM=`cat "$PID_FILE"`;
  kill $PID_NUM
  i=0;
  STOPPED=false;
  
  if [ -z "$NUM_ATTEMPTS" ]; then
        NUM_ATTEMPTS=5
  fi
  #check each second for five seconds to try to let the batch clean up nicely
  while [ $i -lt $NUM_ATTEMPTS ];
  do
    # still alive? ps cax to get all pids, add ~PID string to make sure you match the EXACT process
    RESULT=`ps cax | awk '{print $1"~PID"}' | grep $PID_NUM"~PID" -c`
	if [ $RESULT -eq 0 ]; then
    	echo "Stopped $THIS_APP with pid $PID_NUM";
    	i=11;
    	STOPPED=true;
    	break;
	else
    	sleep 1;
        i=$((i+1))
	fi
  done
  #if we havent stopped the process yet, time to kill 9
  if [ !$STOPPED ]; then
  	kill -9 $PID_NUM
  fi
  
  rm -rf "$PID_FILE"
  PID_NUM=
  
}

status()
{
  cd $BASE_DIR

  if $has_instances; then
    IFS=","
    for i in $INSTANCES
    do
      instance_status $i
    done
  else
    instance_status
  fi

}

instance_status()
{
  INSTANCE=$1

  THIS_APP=$(this_app $INSTANCE)

  if $(instance_running $INSTANCE); then
    echo "$THIS_APP is running with pid " `cat $(pid_file $1)`
  else
    echo "$THIS_APP is not running"
  fi
}

instance_running()
{
  PID_FILE=$(pid_file $1)

  if [ -f $PID_FILE ]; then
    PID=`cat $PID_FILE`
    kill -0 $PID >/dev/null 2>&1
    # if the process is running, return true
    if [ $? -eq 0 ]; then
      echo "true"
      return
    fi
    # otherwise delete the pid file, since the PID in it is invalid
    rm -f $PID_FILE
  fi
  echo "false"
}

pid_file()
{
  INSTANCE=$1
  if $has_instances; then
    PID_FILE=$BASE_DIR/bin/pid-$INSTANCE
  else
    PID_FILE=$BASE_DIR/bin/pid
  fi
  echo $PID_FILE
}

this_app()
{
  INSTANCE=$1
  THIS_APP=$APP_NAME
  if $has_instances; then
    THIS_APP="$THIS_APP instance $INSTANCE"
  fi
  echo $THIS_APP
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  status)
    status
    ;;
  *)
    echo " Usage : $0 (start|stop|restart|status) [instance] "
esac

