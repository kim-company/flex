#!/bin/sh

PUBKEY=${PUBKEY:?Gateway public rsa key is undefined}
PORT=${PORT:?Gateway listening port is undefined}
FILES=${FILES:?Space files path is undefined}

keyfile=rsa.pub
echo $PUBKEY | base64 -d >$keyfile

googlecreds=creds-google.json
echo $GOOGLE_APPLICATION_CREDENTIALS | base64 -d >$googlecreds
export GOOGLE_APPLICATION_CREDENTIALS=$googlecreds

gateway -p $PORT -k $keyfile < $FILES "$@" &

pid=`echo $!`
trap "kill -s SIGINT $pid" SIGHUP SIGINT SIGQUIT SIGTERM
wait $pid
