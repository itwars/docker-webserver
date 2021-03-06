#!/bin/bash
set -e

/consul-dns.sh &

if [ "$CONSUL_SERVICE" ]; then
	export KV_IP=$CONSUL_SERVICE
fi

if [ ! "$MON_IP" ]; then
	if [ "$1" == 'mon' ]; then
		# If we are running monitor - use host IP
		export MON_IP=`cat /etc/hosts | awk '{ print $1; exit }'`
	else
		# Otherwise use host name
		export MON_IP=$CEPH_MON_SERVICE
	fi
fi

if [ ! "$CEPH_PUBLIC_NETWORK" ]; then
	export CEPH_PUBLIC_NETWORK=`ip addr | grep $MON_IP | awk '{ print $2 }'`
fi

if [[ "$1" == 'osd' && "$OSD_TYPE" == 'directory' ]]; then
	if [ "`find /var/lib/ceph/osd -prune -empty`" ]; then
		# From original entrypoint to get all configs from Consul
		source /config.kv.sh
		get_config
		if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
		  echo "ERROR- /etc/ceph/${CLUSTER}.conf must exist; get it from your existing mon"
		  exit 1
		fi
		if [ ${CEPH_GET_ADMIN_KEY} -eq "1" ]; then
			get_admin_key
			if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
				echo "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
				exit 1
			fi
		fi

		OSD_ID=`ceph --cluster $CLUSTER osd create`
		mkdir /var/lib/ceph/osd/$CLUSTER-$OSD_ID
		chown -R ceph: /var/lib/ceph/osd/$CLUSTER-$OSD_ID
	else
		DIRECTORY=`ls -d /var/lib/ceph/osd/* | awk '{ print $1; exit }'`
		OSD_ID=`echo $DIRECTORY | tr '-' ' ' | awk '{ print $2; exit }'`
		# If directory was mounted, but not initialized yet - lets do it
		if [ ! -e $DIRECTORY/fsid ]; then
			chown -R ceph: $DIRECTORY
			# Directory might be named in any way, so lets add symlink with normalized path
			if [ "$OSD_ID" ]; then
				# If OSD id was specified, but is known yet, so lets create OSD with specified id
				if ! ceph --cluster $CLUSTER osd find $OSD_ID; then
					ceph --cluster $CLUSTER osd create `uuidgen` $OSD_ID
				fi
			else
				OSD_ID=`ceph --cluster $CLUSTER osd create`
				ln -s $DIRECTORY /var/lib/ceph/osd/$CLUSTER-$OSD_ID
			fi
		else
			# Even if everything is initialized, directory might be named in any way, so lets add symlink with normalized path
			if [ ! "$OSD_ID" ]; then
				ln -s $DIRECTORY /var/lib/ceph/osd/$CLUSTER-`cat $DIRECTORY/whoami`
			fi
		fi
	fi
fi

exec /entrypoint.sh $@
