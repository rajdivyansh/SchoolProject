#!/bin/bash
CP=
SCRIPT="$0"
SCRIPT_DIR=`dirname ${SCRIPT}`
JAVA_OPTS="-Xms256M -Xmx512M"
if [ "$JAVA_HOME" = "" ]; then \
JAVA_HOME=/usr/java ; \
fi 
OLDD=`pwd`

#JAVA_OPTS="${JAVA_OPTS} -Xdebug -Xrunjdwp:transport=dt_socket,server=y,address=5001,suspend=y"

cd ${SCRIPT_DIR}/..

PARAMFILE=/tmp/params$$${RANDOM}.txt

for jar in `find lib -name "*.jar" -print`; do CP=${jar}:${CP} ; done

echo "-classpath" > ${PARAMFILE}
echo "${CP}" >> ${PARAMFILE}

for opt in ${JAVA_OPTS}; do
   echo "${opt}" >> ${PARAMFILE};
done

echo "<java class>" >> ${PARAMFILE}

while [ "$1" ]; do
   echo "$1" >> ${PARAMFILE};
   shift;
done

IFS=$'\n'
exec "${JAVA_HOME}/bin/java" `cat ${PARAMFILE}`

rm -f ${PARAMFILE}

cd ${OLDD}

