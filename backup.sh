#!/bin/bash

if [ -z $BACKUP_INTERVAL ]
then
	export BACKUP_INTERVAL=300
fi

if [ -z $MYSQL_PASSWORD ]
then
	echo "La variable MYSQL_PASSWORD doit être valorise"
	exit 1
fi

if [ -z $MYSQL_HOST ]
then
	export MYSQL_HOST=database
fi

if [ ! -z $AWS_ACCESS_KEY_ID ]
then
	mkdir -p ~aws/.aws
	echo "[default]" > ~aws/.aws/credentials
	echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> ~aws/.aws/credentials
	echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> ~aws/.aws/credentials
fi

if [ ! -z $AWS_REGION ]
then
	echo "[default]" > ~aws/.aws/config
	echo "region = $AWS_REGION" >> ~aws/.aws/config
fi

while $(true)
do
	export TH=$( date +%Y%m%d_%H%M%S)
	export BACKUP_FILE=/backup/all-databases.$TH.dmp.gz
	echo "Backup de mariadb dans $BACKUP_FILE"
	mysqldump -uroot -p$MYSQL_PASSWORD -h$MYSQL_HOST --all-databases | gzip -c > $BACKUP_FILE
	RC=$?
	if [ "$RC" != "0" ]
	then
		echo "Erreur lors du backup"
		exit 1
	fi
	if [ ! -z $AWS_ACCESS_KEY_ID ]
	then
		aws glacier upload-archive --account-id - --vault-name sauvegardes_techniques --body $BACKUP_FILE
	fi
	echo "Attente $BACKUP_INTERVAL secondes"
	sleep $BACKUP_INTERVAL
done
