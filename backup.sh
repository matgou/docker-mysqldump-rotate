#!/bin/bash

# Load profile
. /etc/profile
. ~/.bashrc

export PATH=$PATH:/home/aws/aws/env/bin/

if [ -z $BACKUP_INTERVAL ]
then
	export BACKUP_INTERVAL=300
fi

if [ -z $MYSQL_PORT ]
then
	export MYSQL_PORT=3306
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

if [ -z $MYSQL_USER ]
then
	export MYSQL_USER=root
fi

if [ -z $MYSQL_DATABASE ]
then
	export MYSQL_DATABASE="--all-databases"
	export BACKUP_NAME="all-databases"
else
	export BACKUP_NAME="$MYSQL_DATABASE"
fi

if [ ! -z $AWS_ACCESS_KEY_ID ]
then
	mkdir -p ~aws/.aws
	echo "[default]" > ~aws/.aws/credentials
	echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> ~aws/.aws/credentials
	echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> ~aws/.aws/credentials
	if [ -z $AWS_VAULT_NAME ]
	then
		echo "La variable AWS_VAULT_NAME doit être valorise si AWS_ACCESS_KEY_ID est valorisé"
		exit 1
	fi
	if [ ! -z $AWS_REGION ]
	then
		echo "[default]" > ~aws/.aws/config
		echo "region = $AWS_REGION" >> ~aws/.aws/config
	fi
fi


while $(true)
do
	find /backup -name "${BACKUP_NAME}*" -mtime 1 | xargs rm -rvf
	export TH=$( date +%Y%m%d_%H%M%S)
	export BACKUP_FILE=/backup/$BACKUP_NAME.$TH.sql.gz
	echo "Backup de mariadb dans $BACKUP_FILE"
	mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -h$MYSQL_HOST -P$MYSQL_PORT $MYSQL_DATABASE | gzip -c > $BACKUP_FILE
	RC=$?
	if [ "$RC" != "0" ]
	then
		echo "Erreur lors du backup"
		exit 1
	fi
	if [ ! -z $AWS_ACCESS_KEY_ID ]
	then
		aws glacier upload-archive --account-id - --vault-name $AWS_VAULT_NAME --body $BACKUP_FILE
		RC=$?
		if [ "$RC" != "0" ]
		then
			echo "Erreur lors de l'upload aws"
			exit 1
		fi
	fi
	echo "Attente $BACKUP_INTERVAL secondes"
	sleep $BACKUP_INTERVAL
	RC=$?
	if [ "$RC" != "0" ]
	then
		echo "Interupted"
		exit $RC
	fi
done
