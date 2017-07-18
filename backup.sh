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
		json=$(aws glacier upload-archive --account-id - --vault-name $AWS_VAULT_NAME --body $BACKUP_FILE)
		RC=$?
		if [ "$RC" != "0" ]
		then
			echo "Erreur lors de l'upload aws"
			exit 1
		fi
		archiveId=$(echo $json | jq .archiveId | sed 's/"//g')
		echo "archiveId=$archiveId"
		mkdir -p /backup/retentionDB/ 2>/dev/null
		echo $archiveId > /backup/retentionDB/$archiveId
		# Par default on garde l'archive 1 journée chez aws
		touch -t `echo $(date +%Y%m%d%H%M -d "1 day")` /backup/retentionDB/$archiveId
		# Recherche si une archive mensuelle existe
		date_1st_3month=$(date +%Y-%m-01 -d "3 month")
		date_2nd_3month=$(date +%Y-%m-02 -d "3 month")
		echo find /backup/retentionDB -type f -newerat $date_1st_3month "!" -newerat $date_2nd_3month
		archiveId_monthly=$(find /backup/retentionDB -type f -newerat $date_1st_3month "!" -newerat $date_2nd_3month)
		echo "Archive mensuelle = $archiveId_monthly"
		if [ "$archiveId_monthly" == "" ]
		then
			echo "Utilisation de l'archive comme archive mensuelle"
			touch -t `echo $(date +%Y%m01 -d "3 month")0800` /backup/retentionDB/$archiveId
		fi
		# Recherche si une archive mensuelle existe
		date_1st_annu=$(date +%Y-01-01 -d "3 years")
		date_2nd_annu=$(date +%Y-01-02 -d "3 years")
		echo find /backup/retentionDB -type f -newerat $date_1st_annu "!" -newerat $date_2nd_annu
		archiveId_annualy=$( find /backup/retentionDB -type f -newerat $date_1st_annu "!" -newerat $date_2nd_annu)
		echo "Archive annuelle = $archiveId_annualy"
		if [ "$archiveId_annualy" == "" ]
		then
			echo "Utilisation de l'archive comme archive annuelle"
			touch -t `echo $(date +%Y0101 -d "3 years")0800` /backup/retentionDB/$archiveId
		fi

		# Suppression des anciennes archives dans glacier
		find /backup/retentionDB -type f -atime +0 | while read file
		do
			echo "Suppression dans glacier de $file"
			aws glacier delete-archive --account-id - --vault-name $AWS_VAULT_NAME --archive-id $(cat $file)
		done
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
